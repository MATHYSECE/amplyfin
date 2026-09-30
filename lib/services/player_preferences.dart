import 'package:shared_preferences/shared_preferences.dart';

import '../models/subtitle_size.dart';

/// Réglages du lecteur retenus sur le téléphone (pour tous les films et
/// séries). Ce ne sont pas des données secrètes : pas besoin du coffre-fort.
class PlayerPreferences {
  static const _subtitleSizeKey = 'subtitle_size';

  Future<SubtitleSize> loadSubtitleSize() async {
    final prefs = await SharedPreferences.getInstance();
    return SubtitleSize.fromName(prefs.getString(_subtitleSizeKey));
  }

  Future<void> saveSubtitleSize(SubtitleSize size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subtitleSizeKey, size.name);
  }
}
