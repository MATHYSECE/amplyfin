import 'package:shared_preferences/shared_preferences.dart';

import 'profile_data.dart';

/// Ce que chaque profil a déjà vu de la découverte de l'appli : la visite
/// guidée (à la première connexion) et l'astuce du lecteur (à la première
/// lecture). Retenu sur l'appareil, sous le profil en cours.
class TourPreferences {
  static const _tour = 'tour_seen';
  static const _playerTip = 'player_tip_seen';

  Future<bool> _get(String name) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(ProfileData.key(name)) ?? false;
  }

  Future<void> _set(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ProfileData.key(name), true);
  }

  /// Vrai si ce profil a déjà vu (ou passé) la visite guidée.
  Future<bool> tourSeen() => _get(_tour);
  Future<void> markTourSeen() => _set(_tour);

  /// Vrai si ce profil a déjà vu l'astuce du lecteur.
  Future<bool> playerTipSeen() => _get(_playerTip);
  Future<void> markPlayerTipSeen() => _set(_playerTip);
}
