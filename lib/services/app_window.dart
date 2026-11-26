import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_capabilities.dart';

/// Fenêtre de l'appli sur PC et Mac : plein écran (code natif dans
/// windows/runner/flutter_window.cpp et macos/Runner/MainFlutterWindow.swift).
/// Sans effet ailleurs.
class AppWindow {
  static const _channel = MethodChannel('amplyfin/window');

  /// Vrai quand la fenêtre occupe tout l'écran, sans bordure.
  static final fullScreen = ValueNotifier<bool>(false);

  /// Écoute le Mac : plein écran quitté ou pris sans l'appli (bouton vert,
  /// Échap). À appeler une fois au démarrage.
  static void listen() {
    if (!DeviceCapabilities.isDesktop) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'fullScreenChanged' && call.arguments is bool) {
        fullScreen.value = call.arguments as bool;
      }
    });
  }

  static Future<void> setFullScreen(bool value) async {
    if (!DeviceCapabilities.isDesktop || fullScreen.value == value) return;
    try {
      await _channel.invokeMethod<void>('setFullScreen', value);
      fullScreen.value = value;
    } on PlatformException {
      // Refusé : la fenêtre reste comme elle est
    } on MissingPluginException {
      // Code natif absent : rien à faire
    }
  }

  static Future<void> toggleFullScreen() => setFullScreen(!fullScreen.value);
}
