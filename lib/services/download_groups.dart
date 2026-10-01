import '../models/download_info.dart';
import '../models/episode.dart';
import '../models/item_details.dart';
import '../models/season.dart';
import '../models/watch_progress.dart';
import 'download_manager.dart';

/// Un téléchargement : identifiant de l'élément, son état et ses infos.
class DownloadEntry {
  const DownloadEntry(this.id, this.state, this.info);

  final String id;
  final DownloadState state;
  final DownloadInfo info;

  bool get isComplete => state.phase == DownloadPhase.complete;

  /// En cours, en attente, en pause, ou en échec (à réessayer).
  bool get isPending => !isComplete;
}

/// Les épisodes téléchargés (ou en cours) d'une série.
class SeriesDownloads {
  SeriesDownloads(this.seriesId, List<DownloadEntry> episodes)
    : episodes = [...episodes]..sort(_byEpisode);

  final String seriesId;

  /// Épisodes, rangés par saison puis par numéro.
  final List<DownloadEntry> episodes;

  DownloadInfo get _first => episodes.first.info;

  String get name => _first.seriesName ?? _first.name;

  /// Infos d'un épisode, pour l'affiche et la fiche de la série.
  DownloadInfo get sample => _first;

  List<DownloadEntry> get complete => [
    for (final e in episodes)
      if (e.isComplete) e,
  ];

  int get pendingCount => episodes.where((e) => e.isPending).length;

  /// Place prise par les épisodes terminés, en octets.
  int get completeBytes =>
      complete.fold(0, (sum, e) => sum + (e.state.size ?? 0));

  /// Épisodes par numéro de saison (dans l'ordre des saisons).
  Map<int?, List<DownloadEntry>> get bySeason {
    final seasons = <int?, List<DownloadEntry>>{};
    for (final e in episodes) {
      (seasons[e.info.seasonNumber] ??= []).add(e);
    }
    return seasons;
  }

  /// Épisode dont la saison s'ouvre sur la fiche de la série : le premier
  /// épisode téléchargé pas encore vu (là où on en est) ; si tout est vu,
  /// le dernier téléchargé. [isWatched] : vrai si l'épisode a été vu.
  DownloadInfo episodeToOpen({
    required bool Function(String itemId) isWatched,
  }) {
    final done = complete;
    if (done.isEmpty) return sample;
    for (final e in done) {
      if (!isWatched(e.id)) return e.info;
    }
    DateTime created(DownloadEntry e) => e.state.createdAt ?? DateTime(2000);
    return done.reduce((a, b) => created(b).isAfter(created(a)) ? b : a).info;
  }

  /// Dernier épisode demandé (pour ranger les séries).
  DateTime get latest => episodes
      .map((e) => e.state.createdAt ?? DateTime(2000))
      .reduce((a, b) => a.isAfter(b) ? a : b);

  static int _byEpisode(DownloadEntry a, DownloadEntry b) {
    final season = (a.info.seasonNumber ?? 0).compareTo(
      b.info.seasonNumber ?? 0,
    );
    if (season != 0) return season;
    return (a.info.episodeNumber ?? 0).compareTo(b.info.episodeNumber ?? 0);
  }
}

/// Les téléchargements rangés pour l'écran « Téléchargements ».
class DownloadGroups {
  const DownloadGroups._({
    required this.pending,
    required this.movies,
    required this.series,
    required this.allSeries,
  });

  /// Range les téléchargements [states]. Ceux de [hidden] (suppression
  /// en attente d'« Annuler ») et ceux dont la fiche n'est pas encore
  /// arrivée sont laissés de côté.
  factory DownloadGroups.of(
    Map<String, DownloadState> states, {
    Set<String> hidden = const {},
  }) {
    final entries = [
      for (final MapEntry(key: id, value: state) in states.entries)
        if (!hidden.contains(id) && state.info != null)
          DownloadEntry(id, state, state.info!),
    ];
    DateTime created(DownloadEntry e) => e.state.createdAt ?? DateTime(2000);

    final pending = [
      for (final e in entries)
        if (e.isPending) e,
    ]..sort((a, b) => created(a).compareTo(created(b)));

    final movies = [
      for (final e in entries)
        if (e.isComplete && !e.info.isEpisode) e,
    ]..sort((a, b) => created(b).compareTo(created(a)));

    final bySeries = <String, List<DownloadEntry>>{};
    for (final e in entries.where((e) => e.info.isEpisode)) {
      (bySeries[e.info.seriesId ?? e.info.seriesName ?? '?'] ??= []).add(e);
    }
    final allSeries = {
      for (final MapEntry(key: id, value: episodes) in bySeries.entries)
        id: SeriesDownloads(id, episodes),
    };
    final series = [
      for (final s in allSeries.values)
        if (s.complete.isNotEmpty) s,
    ]..sort((a, b) => b.latest.compareTo(a.latest));

    return DownloadGroups._(
      pending: pending,
      movies: movies,
      series: series,
      allSeries: allSeries,
    );
  }

  /// Pas encore terminés (en cours, en attente, en pause, en échec), du
  /// plus ancien au plus récent.
  final List<DownloadEntry> pending;

  /// Films terminés, du plus récent au plus ancien.
  final List<DownloadEntry> movies;

  /// Séries ayant au moins un épisode terminé, de la plus récente à la
  /// plus ancienne.
  final List<SeriesDownloads> series;

  /// Toutes les séries, même sans épisode terminé (identifiant → série).
  final Map<String, SeriesDownloads> allSeries;

  bool get isEmpty => pending.isEmpty && movies.isEmpty && series.isEmpty;
}

/// Où en est le téléchargement d'une saison (bouton « Télécharger la
/// saison » de la fiche série).
class SeasonDownloadSummary {
  const SeasonDownloadSummary._({
    required this.total,
    required this.completeIds,
    required this.pendingIds,
    required this.missingIds,
    required this.progress,
    required this.missingBytes,
    required this.completeBytes,
  });

  factory SeasonDownloadSummary.of(
    List<Episode> episodes,
    DownloadState Function(String itemId) stateOf,
  ) {
    final complete = <String>[];
    final pending = <String>[];
    final missing = <String>[];
    int? missingBytes;
    var completeBytes = 0;
    var progress = 0.0;
    for (final episode in episodes) {
      final state = stateOf(episode.id);
      if (state.phase == DownloadPhase.complete) {
        complete.add(episode.id);
        completeBytes += state.size ?? episode.fileSize ?? 0;
        progress += 1;
      } else if (state.isActive) {
        pending.add(episode.id);
        progress += state.progress;
      } else {
        // Jamais téléchargé, ou en échec : à (re)télécharger
        missing.add(episode.id);
        if (episode.fileSize case final size?) {
          missingBytes = (missingBytes ?? 0) + size;
        }
      }
    }
    final tracked = complete.length + pending.length;
    return SeasonDownloadSummary._(
      total: episodes.length,
      completeIds: complete,
      pendingIds: pending,
      missingIds: missing,
      progress: tracked == 0 ? 0 : progress / tracked,
      missingBytes: missingBytes,
      completeBytes: completeBytes,
    );
  }

  final int total;
  final List<String> completeIds;
  final List<String> pendingIds;
  final List<String> missingIds;

  /// Avancée des épisodes demandés (terminés et en cours), de 0 à 1.
  final double progress;

  /// Taille des épisodes pas encore téléchargés (null si inconnue).
  final int? missingBytes;

  /// Place prise par les épisodes terminés, en octets.
  final int completeBytes;

  bool get isDownloading => pendingIds.isNotEmpty;
  bool get isComplete => total > 0 && completeIds.length == total;

  /// Épisodes demandés : terminés et en cours.
  int get tracked => completeIds.length + pendingIds.length;
}

/// Fiche d'une série sans le serveur, faite de ses épisodes téléchargés :
/// infos de la série, saisons (seulement celles qui ont des épisodes
/// téléchargés) et épisodes par saison.
class OfflineSeries {
  const OfflineSeries._({
    required this.details,
    required this.seasons,
    required this.episodes,
  });

  /// [downloaded] : les épisodes téléchargés de la série (au moins un).
  /// [progressOf] : où en est la lecture d'un épisode (null : pas commencé).
  factory OfflineSeries.of(
    List<DownloadInfo> downloaded, {
    WatchProgress? Function(String itemId)? progressOf,
  }) {
    final sorted = [...downloaded]
      ..sort((a, b) {
        final season = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
        if (season != 0) return season;
        return (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
      });
    // Infos de la série : celles d'un épisode qui les a (téléchargement
    // récent)
    final withSeries =
        sorted.where((e) => e.seriesOverview != null).firstOrNull ??
        sorted.first;
    final seasons = <Season>[];
    final episodes = <String, List<Episode>>{};
    for (final info in sorted) {
      final number = info.seasonNumber;
      final id = info.seasonId ?? 'saison-${number ?? '?'}';
      if (!episodes.containsKey(id)) {
        seasons.add(
          Season(
            id: id,
            name: switch (number) {
              null => 'Épisodes',
              0 => 'Spéciaux',
              _ => 'Saison $number',
            },
            number: number,
          ),
        );
      }
      (episodes[id] ??= []).add(
        info.toEpisode(
          progress: progressOf?.call(info.itemId) ?? const WatchProgress(),
        ),
      );
    }
    return OfflineSeries._(
      details: withSeries.toSeriesDetails(),
      seasons: seasons,
      episodes: episodes,
    );
  }

  final ItemDetails details;
  final List<Season> seasons;

  /// Épisodes par identifiant de saison.
  final Map<String, List<Episode>> episodes;
}
