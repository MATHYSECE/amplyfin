import '../api/jellyfin_api.dart';
import 'connection_monitor.dart';
import 'watched_state.dart';

/// Prépare l'appli pour la personne qui vient d'être choisie (ou de se
/// connecter) : on oublie ce qui était retenu pour la précédente, et le suivi
/// de la connexion passe sur son compte. Ses positions hors ligne sont déjà
/// relues par le coffre-fort de session (ProfileData).
void beginProfile(JellyfinApi api, String userId, {required bool online}) {
  WatchedState.instance.reset();
  ConnectionMonitor.instance.start(api, userId, online: online);
}

/// « Qui regarde ? » à l'ouverture : sur une télé et une tablette (partagées
/// en famille) ; le téléphone, lui, rouvre directement le dernier profil.
bool askWhoIsWatching({required bool tv, required bool tablet}) => tv || tablet;

/// Initiales affichées quand une personne n'a pas de photo
/// (« Marie-Claire » → « MC », « jean dupont » → « JD »).
String initialsOf(String name) {
  final words = name
      .trim()
      .split(RegExp(r'[\s\-_.]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((word) => word[0].toUpperCase()).join();
}
