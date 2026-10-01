import 'durations.dart';
import 'episode.dart';
import 'media_item.dart';
import 'media_track.dart';
import 'watch_progress.dart';

/// Un film ou un épisode de la rangée « Continuer à regarder » : commencé
/// (GET /UserItems/Resume), ou prochain épisode d'une série en cours
/// (GET /Shows/NextUp, avec [nextLabel]).
class ResumeEntry {
  const ResumeEntry({
    required this.id,
    required this.poster,
    required this.title,
    required this.subtitle,
    required this.playerTitle,
    required this.progress,
    this.playerSubtitle,
    this.seriesId,
    this.seasonId,
    this.runtime,
    this.tracks = const [],
    this.nextLabel,
  });

  /// [nextLabel] : « Épisode suivant » ou « Nouvel épisode » pour un
  /// épisode pas encore commencé.
  factory ResumeEntry.fromJson(Map<String, dynamic> json, {String? nextLabel}) {
    final progress = WatchProgress.fromUserData(
      json['UserData'] as Map<String, dynamic>?,
    );
    final runtime = ticksToDuration(json['RunTimeTicks'] as int?);
    final tracks = tracksFromStreams(json['MediaStreams'] as List<dynamic>?);

    // Épisode : affiche de la série, et « S5 · É1 » sous le titre
    if (json['Type'] == 'Episode') {
      final episode = Episode.fromJson(json);
      final seriesId = json['SeriesId'] as String?;
      final seriesName = episode.seriesName ?? episode.name;
      final season = episode.seasonNumber;
      final number = episode.number;
      return ResumeEntry(
        id: episode.id,
        poster: MediaItem(
          id: seriesId ?? episode.id,
          name: seriesName,
          type: 'Series',
          posterTag: json['SeriesPrimaryImageTag'] as String?,
        ),
        title: seriesName,
        subtitle: (season != null && number != null)
            ? 'S$season · É$number'
            : episode.name,
        playerTitle: episode.playerTitle,
        playerSubtitle: episode.playerSubtitle,
        seriesId: seriesId,
        seasonId: json['SeasonId'] as String?,
        progress: progress,
        runtime: runtime,
        tracks: tracks,
        nextLabel: nextLabel,
      );
    }

    // Film : son affiche, et son année sous le titre
    final movie = MediaItem.fromJson(json);
    return ResumeEntry(
      id: movie.id,
      poster: movie,
      title: movie.name,
      subtitle: movie.year?.toString() ?? '',
      playerTitle: movie.name,
      progress: progress,
      runtime: runtime,
      tracks: tracks,
    );
  }

  /// Film ou épisode à lire.
  final String id;

  /// Élément dont on montre l'affiche (le film, ou la série de l'épisode).
  final MediaItem poster;

  /// Titre sous l'affiche (le film, ou la série).
  final String title;

  /// Petite ligne sous le titre : année du film, ou « S5 · É1 ».
  final String subtitle;

  /// Titre et petite ligne affichés dans le lecteur.
  final String playerTitle;
  final String? playerSubtitle;

  /// Série de l'épisode (null pour un film) : pour ses langues retenues.
  final String? seriesId;

  /// Saison de l'épisode (null pour un film) : la fiche s'ouvre dessus.
  final String? seasonId;

  final WatchProgress progress;
  final Duration? runtime;

  /// Pistes audio et sous-titres (pour appliquer les langues de la série).
  final List<MediaTrack> tracks;

  /// « Épisode suivant » / « Nouvel épisode » (null : déjà commencé).
  final String? nextLabel;

  bool get isEpisode => seriesId != null;

  /// Vrai pour un épisode suivant, pas encore commencé.
  bool get isNext => nextLabel != null;

  /// Temps restant affiché sur l'affiche : « Reste 14 min ».
  String? get remainingLabel => progress.remainingLabel(runtime);
}
