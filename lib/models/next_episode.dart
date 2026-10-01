import 'download_info.dart';
import 'episode.dart';
import 'media_track.dart';
import 'watch_progress.dart';

/// Épisode à enchaîner à la fin de celui en cours (carte « Épisode suivant »).
class NextEpisode {
  const NextEpisode({
    required this.itemId,
    required this.title,
    this.subtitle,
    this.seriesId,
    this.imageUrl,
    this.imagePath,
    this.tracks = const [],
    this.start = Duration.zero,
  });

  /// Épisode renvoyé par le serveur (GET /Shows/{id}/Episodes).
  factory NextEpisode.fromJson(Map<String, dynamic> json, {String? imageUrl}) {
    final episode = Episode.fromJson(json);
    return NextEpisode(
      itemId: episode.id,
      title: episode.playerTitle,
      subtitle: episode.playerSubtitle,
      seriesId: json['SeriesId'] as String?,
      imageUrl: imageUrl,
      tracks: episode.tracks,
      start: startOf(episode.progress),
    );
  }

  /// Épisode téléchargé (hors ligne). [progress] : où en est sa lecture.
  factory NextEpisode.fromDownload(
    DownloadInfo info, {
    WatchProgress? progress,
    String? imagePath,
  }) => NextEpisode(
    itemId: info.itemId,
    title: info.playerTitle,
    subtitle: info.playerSubtitle,
    seriesId: info.seriesId,
    imagePath: imagePath,
    tracks: info.tracks,
    start: progress == null ? Duration.zero : startOf(progress),
  );

  final String itemId;

  /// Titre en gras dans le lecteur (la série).
  final String title;

  /// « S2 · É4 · Titre de l'épisode ».
  final String? subtitle;
  final String? seriesId;

  /// Vignette de l'épisode : sur le serveur, ou fichier du téléphone.
  final String? imageUrl;
  final String? imagePath;

  /// Pistes du fichier (pour appliquer les langues choisies pour la série).
  final List<MediaTrack> tracks;

  /// Position de départ : là où il s'était arrêté s'il est commencé.
  final Duration start;

  /// Un épisode commencé reprend là où il s'était arrêté, sinon au début.
  static Duration startOf(WatchProgress progress) =>
      progress.canResume ? progress.position : Duration.zero;
}

/// Temps laissé à la carte « Épisode suivant » quand le générique de fin
/// n'est pas connu du serveur.
const nextEpisodeLeadTime = Duration(seconds: 30);

/// Durée du compte à rebours de la carte.
const nextEpisodeCountdown = Duration(seconds: 10);

/// « Tu regardes toujours ? » après ce nombre d'épisodes enchaînés tout
/// seuls sans toucher l'écran.
const stillWatchingAfter = 3;

/// Moment où la carte « Épisode suivant » apparaît : au début du générique
/// de fin ([outroStart]) s'il est connu et plausible (dans la 2e moitié),
/// sinon [nextEpisodeLeadTime] avant la fin. Null tant que la durée est
/// inconnue, ou si la vidéo est trop courte.
Duration? nextEpisodeTrigger(Duration duration, {Duration? outroStart}) {
  if (duration < const Duration(minutes: 2)) return null;
  if (outroStart != null &&
      outroStart > duration ~/ 2 &&
      outroStart < duration - const Duration(seconds: 2)) {
    return outroStart;
  }
  return duration - nextEpisodeLeadTime;
}

/// Épisode téléchargé qui suit [current] dans sa série (ordre saison puis
/// épisode), parmi [downloaded]. Null s'il n'y en a pas.
DownloadInfo? nextDownloaded(
  List<DownloadInfo> downloaded,
  DownloadInfo current,
) {
  int order(DownloadInfo info) =>
      (info.seasonNumber ?? 0) * 100000 + (info.episodeNumber ?? 0);
  final after = [
    for (final info in downloaded)
      if (info.isEpisode &&
          info.seriesId != null &&
          info.seriesId == current.seriesId &&
          order(info) > order(current))
        info,
  ]..sort((a, b) => order(a).compareTo(order(b)));
  return after.firstOrNull;
}
