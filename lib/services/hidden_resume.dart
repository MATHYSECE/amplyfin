import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/resume_entry.dart';
import 'profile_data.dart';

/// « Retirer de Continuer à regarder » en gardant la progression : le
/// serveur ne sait pas cacher un élément sans effacer sa position, l'appli
/// retient donc (par profil) les éléments masqués et la position qu'ils
/// avaient. Relancé ensuite (la position bouge), l'élément réapparaît.
class HiddenResume {
  static const _name = 'hidden_resume';

  /// Éléments masqués du profil en cours : identifiant → position (ms).
  Future<Map<String, int>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(ProfileData.key(_name));
    if (text == null) return {};
    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      return {
        for (final MapEntry(:key, :value) in map.entries)
          if (value is int) key: value,
      };
    } on FormatException {
      return {};
    }
  }

  Future<void> _save(Map<String, int> hidden) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ProfileData.key(_name), jsonEncode(hidden));
  }

  /// Masque [itemId], arrêté à [position].
  Future<void> hide(String itemId, Duration position) async {
    final hidden = await load();
    hidden[itemId] = position.inMilliseconds;
    await _save(hidden);
  }

  /// Ne masque plus [itemId] (« Annuler »).
  Future<void> show(String itemId) async {
    final hidden = await load();
    if (hidden.remove(itemId) != null) await _save(hidden);
  }

  /// Retire les éléments masqués de [entries], et oublie ceux qui ont été
  /// relancés depuis.
  Future<List<ResumeEntry>> filter(List<ResumeEntry> entries) async {
    final hidden = await load();
    if (hidden.isEmpty) return entries;
    final result = applyHiddenResume(entries, hidden);
    if (result.stale.isNotEmpty) {
      hidden.removeWhere((id, _) => result.stale.contains(id));
      await _save(hidden);
    }
    return result.visible;
  }
}

/// Écart de position toléré : au-delà, l'élément a été relancé.
const _tolerance = Duration(seconds: 2);

/// Sépare les entrées à afficher ([visible]) des éléments masqués à oublier
/// ([stale]) : ceux dont la position a bougé depuis. Un élément absent de
/// la liste reste retenu (le serveur a pu mal répondre cette fois-ci).
({List<ResumeEntry> visible, Set<String> stale}) applyHiddenResume(
  List<ResumeEntry> entries,
  Map<String, int> hidden,
) {
  final stale = <String>{};
  final visible = <ResumeEntry>[];
  for (final entry in entries) {
    final saved = hidden[entry.id];
    if (saved == null) {
      visible.add(entry);
      continue;
    }
    final moved =
        (entry.progress.position.inMilliseconds - saved).abs() >
        _tolerance.inMilliseconds;
    if (moved) {
      visible.add(entry);
      stale.add(entry.id);
    }
  }
  return (visible: visible, stale: stale);
}
