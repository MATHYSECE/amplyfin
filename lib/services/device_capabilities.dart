import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../models/device_decoders.dart';
import '../models/player_codecs.dart';

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
    final emulator = await isAndroidEmulator();
    final player = playerCodecs = await _readPlayerCodecs();
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>('decoders');
      if (map != null) {
        return DeviceDecoders.fromMap(
          map,
          allow10Bit: !emulator,
          player: player,
        );
      }
    } on PlatformException {
      // Réponse impossible : tout accepté
    } on MissingPluginException {
      // Code natif absent (tests, autre système) : tout accepté
    }
    return DeviceDecoders(allow10Bit: !emulator, player: player);
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
