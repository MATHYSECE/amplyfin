/// Les informations d'une connexion réussie à un serveur Jellyfin.
/// Le mot de passe n'en fait jamais partie : seul le jeton est conservé.
/// Chaque personne connectée sur l'appareil a la sienne (un « profil »).
class Session {
  const Session({
    required this.serverUrl,
    required this.accessToken,
    required this.userId,
    required this.userName,
    this.imageTag,
  });

  /// Adresse du serveur, sans « / » final (ex. http://192.168.1.10:8096).
  final String serverUrl;

  /// Jeton renvoyé par le serveur après la connexion.
  final String accessToken;

  /// Identifiant de l'utilisateur sur le serveur.
  final String userId;

  /// Nom affiché de l'utilisateur.
  final String userName;

  /// Version de la photo de profil Jellyfin (null : pas de photo, on
  /// affiche les initiales).
  final String? imageTag;

  /// Même session avec le nom et la photo relus sur le serveur.
  Session withProfile({required String userName, String? imageTag}) => Session(
    serverUrl: serverUrl,
    accessToken: accessToken,
    userId: userId,
    userName: userName,
    imageTag: imageTag,
  );

  /// Même personne sur le même serveur (un seul profil par compte).
  bool sameAccount(Session other) =>
      other.serverUrl == serverUrl && other.userId == userId;

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'accessToken': accessToken,
    'userId': userId,
    'userName': userName,
    'imageTag': imageTag,
  };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    serverUrl: json['serverUrl'] as String,
    accessToken: json['accessToken'] as String,
    userId: json['userId'] as String,
    userName: (json['userName'] as String?) ?? '',
    imageTag: json['imageTag'] as String?,
  );
}
