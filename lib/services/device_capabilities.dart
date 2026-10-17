import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../models/device_decoders.dart';
import '../models/player_codecs.dart';
import 'video_engine.dart';

/// Ce que l'appareil sait faire (vérifié une seule fois, puis retenu).
class DeviceCapabilities {
  static bool? _emulator;
  static Future<DeviceDecoders>? _decoders;

  /// Formats décodés par le lecteur : la liste connue d'avance, puis celle
  /// donnée par le lecteur une fois [decoders] terminé.
  static PlayerCodecs playerCodecs = PlayerCodecs.builtIn;

  /// Code natif qui interroge la puce vidéo (MainActivity.kt sur Android,
  /// AppDelegate.swift sur iPhone).
  static const _channel = MethodChannel('amplyfin/device');

  /// Vrai sur une télé (Fire TV, Android TV, Samsung) : interface à la
  /// télécommande, pas de téléchargements. Connu dès le démarrage
  /// ([detectTv]).
  static bool isTv = false;

  /// Vrai sur une télé Samsung (Tizen) : Dart la voit comme un Linux, mais
  /// flutter-tizen donne la version de Tizen dans l'environnement.
  static final bool isTizen = Platform.environment.containsKey(
    'TIZEN_API_VERSION',
  );

  /// Vrai sur un ordinateur (Windows) : souris et clavier, fenêtre, pas de
  /// luminosité ni de données mobiles. Connu dès le démarrage
  /// ([detectDesktop]) ; reste faux dans les tests.
  static bool isDesktop = false;

  /// Nom de l'appareil dans les textes de l'appli (« effacé du PC »).
  static String get deviceWord => isDesktop ? 'PC' : 'téléphone';

  /// Repère si l'appli tourne sur un ordinateur (au démarrage).
  static void detectDesktop() {
    isDesktop = Platform.isWindows;
  }

  /// Demande au téléphone s'il est une télé (une seule fois, au démarrage).
  static Future<void> detectTv() async {
    // Tizen : l'appli n'est publiée que pour les télés
    if (isTizen) {
      isTv = true;
      return;
    }
    if (!Platform.isAndroid) return;
    try {
      isTv = await _channel.invokeMethod<bool>('isTv') ?? false;
    } on PlatformException {
      isTv = false;
    } on MissingPluginException {
      isTv = false;
    }
  }

  /// Vrai sur un émulateur Android : son affichage vidéo et son décodeur
  /// ont des limites (pas d'OpenGL pour le lecteur, pas de vidéo 10 bits).
  static Future<bool> isAndroidEmulator() async {
    final known = _emulator;
    if (known != null) return known;
    var emulator = false;
    if (Platform.isAndroid) {
      final device = await DeviceInfoPlugin().androidInfo;
      emulator = !device.isPhysicalDevice;
    }
    return _emulator = emulator;
  }

  /// Ce que la puce vidéo sait décoder (formats, définition, 10 bits) et si
  /// l'écran est HDR. Si le téléphone ne répond pas, tout est accepté
  /// (comme avant), sauf le 10 bits sur l'émulateur.
  static Future<DeviceDecoders> decoders() => _decoders ??= _readDecoders();

  static Future<DeviceDecoders> _readDecoders() async {
    if (isTizen) return _tizenDecoders;
    final emulator = await isAndroidEmulator();
    Map<Object?, Object?>? map;
    try {
      map = await _channel.invokeMapMethod<Object?, Object?>('decoders');
    } on PlatformException {
      // Réponse impossible : tout accepté
    } on MissingPluginException {
      // Code natif absent (tests, autre système) : tout accepté
    }
    // ExoPlayer (Android) : les décodeurs d'Android ; mpv : les siens
    final player = playerCodecs = usesExoPlayer
        ? PlayerCodecs.android(map?['types'] as List<Object?>?)
        : await _readPlayerCodecs();
    if (map != null) {
      return DeviceDecoders.fromMap(map, allow10Bit: !emulator, player: player);
    }
    return DeviceDecoders(allow10Bit: !emulator, player: player);
  }

  /// Télé Samsung : la télé ne répond pas sur ses décodeurs → ce que lisent
  /// les télés Samsung récentes (4K et 10 bits / HDR10 par la puce ; le
  /// Dolby Vision pur est déjà converti pour tous les appareils).
  static DeviceDecoders get _tizenDecoders {
    playerCodecs = PlayerCodecs.tizen;
    const chip = CodecSupport(
      hardware: true,
      maxWidth: 3840,
      maxHeight: 2160,
      tenBit: true,
    );
    // H.264 en 10 bits (rare, dessins animés) : pas lu par les télés
    const h264 = CodecSupport(hardware: true, maxWidth: 3840, maxHeight: 2160);
    return const DeviceDecoders(
      codecs: {'h264': h264, 'hevc': chip, 'av1': chip, 'vp9': chip},
      hdrScreen: true,
      player: PlayerCodecs.tizen,
    );
  }

  /// Demande la liste de ses décodeurs à un lecteur caché, créé pour
  /// l'occasion. Pas de réponse : la liste connue d'avance.
  static Future<PlayerCodecs> _readPlayerCodecs() async {
    Player? player;
    try {
      player = Player();
      final platform = player.platform;
      if (platform is! NativePlayer) return PlayerCodecs.builtIn;
      final text = await platform
          .getProperty('decoder-list')
          .timeout(const Duration(seconds: 5));
      return PlayerCodecs.fromDecoderList(text) ?? PlayerCodecs.builtIn;
    } on Object {
      // Lecteur indisponible (tests…) ou trop lent
      return PlayerCodecs.builtIn;
    } finally {
      await player?.dispose();
    }
  }
}
