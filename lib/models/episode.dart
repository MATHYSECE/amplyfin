import 'durations.dart';
import 'media_quality.dart';
import 'media_track.dart';

/// Un épisode d'une série (GET /Shows/{id}/Episodes).
class Episode {
  const Episode({
    required this.id,
    required this.name,
    this.seriesName,
    this.seasonNumber,
    this.number,
    this.overview,
    this.runtime,
    this.imageTag,
    this.played = false,
    this.quality,
    this.tracks = const [],
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] as Map<String, dynamic>?;
    final userData = json['UserData'] as Map<String, dynamic>?;
    return Episode(
      id: json['Id'] as String,
      name: (json['Name'] as String?) ?? 'Sans titre',
      seriesName: json['SeriesName'] as String?,
      seasonNumber: json['ParentIndexNumber'] as int?,
      number: json['IndexNumber'] as int?,
      overview: json['Overview'] as String?,
      runtime: ticksToDuration(json['RunTimeTicks'] as int?),
      imageTag: imageTags?['Primary'] as String?,
      played: userData?['Played'] == true,
      quality: MediaQuality.fromItemJson(json),
      tracks: tracksFromStreams(json['MediaStreams'] as List<dynamic>?),
    );
  }

  final String id;

  /// Titre de l'épisode.
  final String name;

  /// Nom de la série.
  final String? seriesName;

  /// Numéro de la saison.
  final int? seasonNumber;

  /// Numéro de l'épisode dans la saison.
  final int? number;

  final String? overview;
  final Duration? runtime;

  /// Empreinte de la vignette de l'épisode (null s'il n'y en a pas).
  final String? imageTag;

  /// Vrai si l'épisode a déjà été vu.
  final bool played;

  /// Qualité technique du fichier (définition, codec, son), si connue.
  final MediaQuality? quality;

  /// Pistes audio et sous-titres (pour appliquer le choix de langue).
  final List<MediaTrack> tracks;

  /// Titre dans la liste : « 3. Titre de l'épisode ».
  String get listTitle => number == null ? name : '$number. $name';

  /// Code court : « S1E3 ».
  String? get code => (seasonNumber != null && number != null)
      ? 'S${seasonNumber}E$number'
      : null;

  /// Titre en gras dans le lecteur : la série (ou l'épisode seul).
  String get playerTitle => seriesName ?? name;

  /// Petite ligne sous le titre du lecteur : « S1 · É3 · Titre ».
  String? get playerSubtitle {
    if (seriesName == null) return null;
    final shortCode = (seasonNumber != null && number != null)
        ? 'S$seasonNumber · É$number'
        : null;
    return [?shortCode, name].join(' · ');
  }

  String? get runtimeLabel => formatRuntime(runtime);

  /// Ligne d'infos sous le titre : « 47 min · 1080p · HEVC · E-AC3 5.1 ».
  String get infoLine => [?runtimeLabel, ...?quality?.labels].join(' · ');
}
