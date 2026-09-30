/// Les informations d'une connexion réussie à un serveur Jellyfin.
/// Le mot de passe n'en fait jamais partie : seul le jeton est conservé.
class Session {
  const Session({
    required this.serverUrl,
    required this.accessToken,
    required this.userId,
    required this.userName,
  });

  /// Adresse du serveur, sans « / » final (ex. http://192.168.1.10:8096).
  final String serverUrl;

  /// Jeton renvoyé par le serveur après la connexion.
  final String accessToken;

  /// Identifiant de l'utilisateur sur le serveur.
  final String userId;

  /// Nom affiché de l'utilisateur.
  final String userName;
}
