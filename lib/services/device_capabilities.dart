import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

import '../models/device_decoders.dart';

/// Ce que l'appareil sait faire (vérifié une seule fois, puis retenu).
class DeviceCapabilities {
  static bool? _emulator;
  static Future<DeviceDecoders>? _decoders;

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
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>('decoders');
      if (map != null) {
        return DeviceDecoders.fromMap(map, allow10Bit: !emulator);
      }
    } on PlatformException {
      // Réponse impossible : tout accepté
    } on MissingPluginException {
      // Code natif absent (tests, autre système) : tout accepté
    }
    return DeviceDecoders(allow10Bit: !emulator);
  }
}
