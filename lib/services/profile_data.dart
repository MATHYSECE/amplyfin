import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'offline_progress.dart';

/// Données propres à chaque personne, rangées sur l'appareil sous son profil
/// (positions hors ligne, recherches récentes, langues par série) : chaque
/// nom de case commence par `profile.<identifiant>.`.
/// Les téléchargements et les réglages d'affichage restent communs.
class ProfileData {
  ProfileData._();

  static String? _userId;

  /// Profil en cours (null si personne n'est connecté).
  static String? get userId => _userId;

  /// Change de profil : les données de cette personne sont relues.
  static void use(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    unawaited(OfflineProgress.instance.init());
  }

  /// Nom de case de [name] pour le profil [userId] (par défaut, celui en
  /// cours).
  static String key(String name, {String? userId}) =>
      'profile.${userId ?? _userId}.$name';

  /// Cases d'avant les profils (un seul compte par appareil).
  static const _legacyKeys = ['offline_progress', 'search_history'];
  static const _legacyPrefixes = ['series_languages_'];

  /// Passage aux profils : les données d'avant (un seul compte) sont rangées
  /// sous le profil [userId], celui de la personne déjà connectée.
  static Future<void> adoptLegacy(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final old in prefs.getKeys().toList()) {
      final legacy =
          _legacyKeys.contains(old) ||
          _legacyPrefixes.any((prefix) => old.startsWith(prefix));
      if (!legacy) continue;
      final value = prefs.get(old);
      final renamed = key(old, userId: userId);
      if (value is String) await prefs.setString(renamed, value);
      if (value is List) {
        await prefs.setStringList(renamed, value.cast<String>());
      }
      await prefs.remove(old);
    }
  }
}
