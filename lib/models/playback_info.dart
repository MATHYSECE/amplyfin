import 'media_track.dart';
import 'transcode_reasons.dart';

/// Réponse du serveur à POST /Items/{id}/PlaybackInfo :
/// comment lire ce film (directement, ou via un flux converti).
class PlaybackInfo {
  const PlaybackInfo({
    required this.itemId,
    required this.mediaSourceId,
    required this.playSessionId,
    required this.directPlay,
    this.transcodingUrl,
    this.tracks = const [],
    this.defaultAudioIndex,
    this.defaultSubtitleIndex,
    this.hasVideo = true,
    this.videoCodec,
    this.localPath,
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
    final streams = ((source['MediaStreams'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();
    final video = streams.where((s) => s['Type'] == 'Video').firstOrNull;
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
      tracks: tracksFromStreams(source['MediaStreams'] as List<dynamic>?),
      defaultAudioIndex: source['DefaultAudioStreamIndex'] as int?,
      defaultSubtitleIndex: source['DefaultSubtitleStreamIndex'] as int?,
      hasVideo: video != null,
      videoCodec: (video?['Codec'] as String?)?.toLowerCase(),
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

  /// Pistes audio et sous-titres (avec, pour les sous-titres, la façon dont
  /// le serveur les livre).
  final List<MediaTrack> tracks;

  /// Piste audio à utiliser : celle demandée, sinon le choix du serveur.
  final int? defaultAudioIndex;

  /// Sous-titres à afficher (-1 = aucun).
  final int? defaultSubtitleIndex;

  /// Vrai si le fichier contient une image (pas seulement du son).
  final bool hasVideo;

  /// Format de l'image du fichier d'origine (« hevc »…), null si inconnu.
  final String? videoCodec;

  /// Fichier téléchargé sur le téléphone (null : lecture depuis le serveur).
  final String? localPath;

  /// Vrai si on lit le fichier téléchargé, sans passer par le serveur.
  bool get isLocal => localPath != null;

  /// Codes des raisons de la conversion, donnés par le serveur dans
  /// l'adresse du flux converti (« TranscodeReasons=… »). Vide en lecture
  /// directe.
  List<String> get transcodeReasons {
    final url = transcodingUrl;
    if (directPlay || url == null) return const [];
    final query = Uri.parse(url).queryParameters;
    final key = query.keys
        .where((k) => k.toLowerCase() == 'transcodereasons')
        .firstOrNull;
    final value = key == null ? '' : query[key]!;
    return [
      for (final code in value.split(','))
        if (code.trim().isNotEmpty) code.trim(),
    ];
  }

  /// Vrai si le serveur ne convertit que le son : toutes les raisons
  /// concernent le son, et l'image est dans un format que le flux converti
  /// accepte tel quel ([copyableVideoCodecs]), donc recopiée sans perte.
  bool convertsOnlyAudio(List<String> copyableVideoCodecs) {
    final reasons = transcodeReasons;
    final url = transcodingUrl?.toLowerCase() ?? '';
    return !directPlay &&
        reasons.isNotEmpty &&
        reasons.every(audioTranscodeReasons.contains) &&
        copyableVideoCodecs.contains(videoCodec) &&
        !url.contains('allowvideostreamcopy=false');
  }

  List<MediaTrack> get audioTracks =>
      tracks.where((t) => t.type == TrackType.audio).toList();

  List<MediaTrack> get subtitleTracks =>
      tracks.where((t) => t.type == TrackType.subtitle).toList();

  /// La piste portant ce numéro, ou null.
  MediaTrack? track(int? index) =>
      tracks.where((t) => t.index == index).firstOrNull;

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
