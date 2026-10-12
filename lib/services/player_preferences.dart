import 'package:shared_preferences/shared_preferences.dart';

import '../models/subtitle_size.dart';

/// Réglages du lecteur retenus sur le téléphone (pour tous les films et
/// séries). Ce ne sont pas des données secrètes : pas besoin du coffre-fort.
class PlayerPreferences {
  static const _subtitleSizeKey = 'subtitle_size';
  static const _volumeKey = 'player_volume';

  Future<SubtitleSize> loadSubtitleSize() async {
    final prefs = await SharedPreferences.getInstance();
    return SubtitleSize.fromName(prefs.getString(_subtitleSizeKey));
  }

  Future<void> saveSubtitleSize(SubtitleSize size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subtitleSizeKey, size.name);
  }

  /// Volume du lecteur sur PC (de 0 à 1) ; sur téléphone, c'est celui du
  /// système. Au maximum la première fois.
  Future<double> loadVolume() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getDouble(_volumeKey) ?? 1.0).clamp(0.0, 1.0);
  }

  Future<void> saveVolume(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, volume);
  }
}
