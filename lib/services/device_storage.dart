import 'package:flutter/services.dart';

/// Place sur le téléphone, en octets.
class DeviceSpace {
  const DeviceSpace({required this.free, required this.total});

  final int free;
  final int total;
}

/// Demande au téléphone la place libre et totale (code natif dans
/// MainActivity.kt sur Android, AppDelegate.swift sur iPhone).
abstract final class DeviceStorage {
  static const _channel = MethodChannel('amplyfin/storage');

  /// Null si le téléphone ne répond pas.
  static Future<DeviceSpace?> read() async {
    try {
      final values = await _channel.invokeMapMethod<String, int>('space');
      final free = values?['free'];
      final total = values?['total'];
      if (free == null || total == null || total <= 0) return null;
      return DeviceSpace(free: free, total: total);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
