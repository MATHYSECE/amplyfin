import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/track_choice.dart';

/// Retient, sur le téléphone, les langues choisies pour chaque série.
/// Ce ne sont pas des données secrètes : pas besoin du coffre-fort.
class TrackPreferences {
  static const _prefix = 'series_languages_';

  /// Choix enregistré pour cette série (réglages par défaut s'il n'y en a pas).
  Future<LanguagePreference> load(String seriesId) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('$_prefix$seriesId');
    if (saved == null) return const LanguagePreference();
    try {
      return LanguagePreference.fromJson(
        jsonDecode(saved) as Map<String, dynamic>,
      );
    } on FormatException {
      return const LanguagePreference();
    }
  }

  Future<void> save(String seriesId, LanguagePreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$seriesId', jsonEncode(preference.toJson()));
  }
}
