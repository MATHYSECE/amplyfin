/// Réponse du serveur à POST /Items/{id}/PlaybackInfo :
/// comment lire ce film (directement, ou via un flux converti).
class PlaybackInfo {
  const PlaybackInfo({
    required this.itemId,
    required this.mediaSourceId,
    required this.playSessionId,
    required this.directPlay,
    this.transcodingUrl,
  });

  /// Lit la réponse. Lève une [FormatException] si le film ne peut pas
  /// être lu (aucune source, ou refus du serveur).
  factory PlaybackInfo.fromJson(
    Map<String, dynamic> json, {
    required String itemId,
  }) {
    final errorCode = json['ErrorCode'] as String?;
    if (errorCode != null) {
      throw FormatException(_errorMessage(errorCode));
    }
    final sources = (json['MediaSources'] as List<dynamic>?) ?? [];
    if (sources.isEmpty) {
      throw const FormatException('Aucune vidéo trouvée pour ce film.');
    }
    final source = sources.first as Map<String, dynamic>;
    final directPlay = source['SupportsDirectPlay'] == true;
    final transcodingUrl = source['TranscodingUrl'] as String?;
    if (!directPlay && transcodingUrl == null) {
      throw const FormatException('Le serveur ne propose aucun flux lisible.');
    }
    return PlaybackInfo(
      itemId: itemId,
      mediaSourceId: source['Id'] as String,
      playSessionId: (json['PlaySessionId'] as String?) ?? '',
      directPlay: directPlay,
      transcodingUrl: transcodingUrl,
    );
  }

  /// Identifiant du film.
  final String itemId;

  /// Identifiant du fichier vidéo choisi sur le serveur.
  final String mediaSourceId;

  /// Identifiant de cette séance de lecture (pour les signalements).
  final String playSessionId;

  /// Vrai : le fichier original est lu tel quel, sans conversion.
  final bool directPlay;

  /// Adresse (partielle) du flux HLS converti, si le serveur en propose un.
  final String? transcodingUrl;

  /// Méthode de lecture, dans le vocabulaire du serveur.
  String get playMethod => directPlay ? 'DirectPlay' : 'Transcode';
}

/// Messages lisibles pour les codes d'erreur de Jellyfin.
String _errorMessage(String code) => switch (code) {
  'NotAllowed' => 'Ton compte n\'a pas le droit de lire ce film.',
  'NoCompatibleStream' => 'Aucun flux compatible avec cet appareil.',
  'RateLimitExceeded' => 'Trop de lectures en cours sur le serveur.',
  _ => 'Lecture refusée par le serveur ($code).',
};
