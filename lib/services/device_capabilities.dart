import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Ce que l'appareil sait faire (vérifié une seule fois, puis retenu).
class DeviceCapabilities {
  static bool? _emulator;

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
}
