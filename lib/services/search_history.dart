import 'package:shared_preferences/shared_preferences.dart';

import '../models/search_results.dart';
import 'profile_data.dart';

/// Recherches récentes du profil en cours, gardées sur le téléphone (les 10
/// dernières).
class SearchHistory {
  static String get _key => ProfileData.key('search_history');

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  /// Ajoute [term] en tête (et renvoie la nouvelle liste).
  Future<List<String>> add(String term) async =>
      _save(addToHistory(await load(), term));

  /// Retire une recherche (et renvoie la nouvelle liste).
  Future<List<String>> remove(String term) async => _save([
    for (final old in await load())
      if (old != term) old,
  ]);

  Future<List<String>> clear() => _save(const []);

  Future<List<String>> _save(List<String> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, history);
    return history;
  }
}
