import 'durations.dart';
import 'media_item.dart';
import 'media_track.dart';
import 'playback_info.dart';

/// Ce qu'on garde d'un film ou d'un épisode téléchargé, pour l'afficher et
/// le lire sans le serveur. Enregistré avec le téléchargement lui-même.
class DownloadInfo {
  const DownloadInfo({
    required this.itemId,
    required this.name,
    required this.mediaSourceId,
    this.isEpisode = false,
    this.seriesId,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.year,
    this.runtime,
    this.posterTag,
    this.container,
    this.size,
    this.streams = const [],
    this.defaultAudioIndex,
    this.defaultSubtitleIndex,
  });

  /// Lit la fiche complète renvoyée par GET /Items/{id} au moment du
  /// téléchargement (premier fichier vidéo de l'élément).
  factory DownloadInfo.fromItemJson(Map<String, dynamic> json) {
    final sources = (json['MediaSources'] as List<dynamic>?) ?? [];
    final source = sources.isEmpty
        ? const <String, dynamic>{}
        : sources.first as Map<String, dynamic>;
    final isEpisode = json['Type'] == 'Episode';
    final imageTags = json['ImageTags'] as Map<String, dynamic>?;
    return DownloadInfo(
      itemId: json['Id'] as String,
      name: (json['Name'] as String?) ?? 'Sans titre',
      mediaSourceId: (source['Id'] as String?) ?? json['Id'] as String,
      isEpisode: isEpisode,
      seriesId: json['SeriesId'] as String?,
      seriesName: json['SeriesName'] as String?,
      seasonNumber: json['ParentIndexNumber'] as int?,
      episodeNumber: json['IndexNumber'] as int?,
      year: json['ProductionYear'] as int?,
      runtime: ticksToDuration(json['RunTimeTicks'] as int?),
      // Épisode : l'affiche de la série ; film : la sienne
      posterTag: isEpisode
          ? json['SeriesPrimaryImageTag'] as String?
          : imageTags?['Primary'] as String?,
      container: (source['Container'] ?? json['Container']) as String?,
      size: source['Size'] as int?,
      streams:
          (source['MediaStreams'] ?? json['MediaStreams'] ?? const [])
              as List<dynamic>,
      defaultAudioIndex: source['DefaultAudioStreamIndex'] as int?,
      defaultSubtitleIndex: source['DefaultSubtitleStreamIndex'] as int?,
    );
  }

  /// Relit les infos enregistrées avec le téléchargement.
  factory DownloadInfo.fromJson(Map<String, dynamic> json) => DownloadInfo(
    itemId: json['itemId'] as String,
    name: json['name'] as String,
    mediaSourceId: json['mediaSourceId'] as String,
    isEpisode: json['isEpisode'] == true,
    seriesId: json['seriesId'] as String?,
    seriesName: json['seriesName'] as String?,
    seasonNumber: json['seasonNumber'] as int?,
    episodeNumber: json['episodeNumber'] as int?,
    year: json['year'] as int?,
    runtime: ticksToDuration(json['runtimeTicks'] as int?),
    posterTag: json['posterTag'] as String?,
    container: json['container'] as String?,
    size: json['size'] as int?,
    streams: (json['streams'] as List<dynamic>?) ?? const [],
    defaultAudioIndex: json['defaultAudioIndex'] as int?,
    defaultSubtitleIndex: json['defaultSubtitleIndex'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'name': name,
    'mediaSourceId': mediaSourceId,
    'isEpisode': isEpisode,
    'seriesId': seriesId,
    'seriesName': seriesName,
    'seasonNumber': seasonNumber,
    'episodeNumber': episodeNumber,
    'year': year,
    'runtimeTicks': runtime == null ? null : durationToTicks(runtime!),
    'posterTag': posterTag,
    'container': container,
    'size': size,
    'streams': streams,
    'defaultAudioIndex': defaultAudioIndex,
    'defaultSubtitleIndex': defaultSubtitleIndex,
  };

  final String itemId;

  /// Titre du film, ou de l'épisode.
  final String name;

  /// Identifiant du fichier vidéo sur le serveur.
  final String mediaSourceId;

  final bool isEpisode;
  final String? seriesId;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? year;
  final Duration? runtime;

  /// Empreinte de l'affiche (du film, ou de la série de l'épisode).
  final String? posterTag;

  /// Format du fichier pour le serveur (« mkv », « mov,mp4,… »).
  final String? container;

  /// Taille du fichier, en octets (si le serveur la connaît).
  final int? size;

  /// Pistes du fichier, telles que renvoyées par le serveur.
  final List<dynamic> streams;

  final int? defaultAudioIndex;
  final int? defaultSubtitleIndex;

  List<MediaTrack> get tracks => tracksFromStreams(streams);

  /// Sous-titres en fichier séparé sur le serveur : téléchargés à part.
  List<MediaTrack> get externalSubtitles => [
    for (final track in tracks)
      if (track.type == TrackType.subtitle && track.isExternal) track,
  ];

  /// Nom du fichier sur le téléphone (l'extension aide à s'y retrouver ;
  /// le lecteur, lui, reconnaît le format tout seul).
  String get fileName {
    final extension = (container ?? '').split(',').first.trim();
    final safe = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(extension)
        ? extension
        : 'video';
    return '$itemId.$safe';
  }

  /// Élément dont on montre l'affiche (le film, ou la série de l'épisode).
  MediaItem get posterItem => MediaItem(
    id: isEpisode ? (seriesId ?? itemId) : itemId,
    name: isEpisode ? (seriesName ?? name) : name,
    type: isEpisode ? 'Series' : 'Movie',
    year: year,
    posterTag: posterTag,
  );

  /// Nom affiché dans les notifications : « 1917 » ou « Malcolm · S5E1 ».
  String get displayName {
    final code = (seasonNumber != null && episodeNumber != null)
        ? 'S${seasonNumber}E$episodeNumber'
        : null;
    if (!isEpisode) return name;
    return [seriesName ?? name, ?code].join(' · ');
  }

  /// Titre en gras dans le lecteur : la série (ou le film).
  String get playerTitle => isEpisode ? (seriesName ?? name) : name;

  /// Petite ligne sous le titre du lecteur : « S5 · É1 · Las Vegas ».
  String? get playerSubtitle {
    if (!isEpisode) return null;
    final code = (seasonNumber != null && episodeNumber != null)
        ? 'S$seasonNumber · É$episodeNumber'
        : null;
    return [?code, name].join(' · ');
  }

  /// Comment lire le fichier téléchargé : lecture directe du fichier
  /// [filePath], sous-titres séparés pris dans [subtitleFiles]
  /// (numéro de piste → fichier sur le téléphone).
  PlaybackInfo localPlaybackInfo(
    String filePath, {
    Map<int, String> subtitleFiles = const {},
  }) {
    final localTracks = [
      for (final track in tracks)
        if (track.isExternal && subtitleFiles.containsKey(track.index))
          MediaTrack(
            index: track.index,
            type: track.type,
            language: track.language,
            codec: track.codec,
            title: track.title,
            isForced: track.isForced,
            isDefault: track.isDefault,
            isExternal: true,
            deliveryMethod: 'External',
            deliveryUrl: Uri.file(subtitleFiles[track.index]!).toString(),
          )
        else if (!track.isExternal)
          track,
    ];
    return PlaybackInfo(
      itemId: itemId,
      mediaSourceId: mediaSourceId,
      playSessionId: '',
      directPlay: true,
      tracks: localTracks,
      defaultAudioIndex: defaultAudioIndex,
      defaultSubtitleIndex: defaultSubtitleIndex,
      localPath: filePath,
    );
  }
}
