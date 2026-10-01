import 'item_details.dart';
import 'media_item.dart';
import 'resume_entry.dart';
import 'watch_progress.dart';

/// Ce qu'affiche la page d'accueil, et les petites règles pour le ranger.

/// Une nouveauté de « À la une » : un film ajouté, ou une série qui a de
/// nouveaux épisodes.
class HeroItem {
  const HeroItem({required this.details, required this.eyebrow});

  final ItemDetails details;

  /// Petit texte au-dessus du titre : « Nouveau film », « 3 nouveaux
  /// épisodes ».
  final String eyebrow;

  MediaItem get item => details.item;
  bool get isSeries => item.isSeries;

  /// « 2024 · Science-fiction · 2 h 46 ».
  String get infoLine => [
    if (details.yearsLabel != null) details.yearsLabel!,
    ...details.genres.take(2),
    ?details.runtimeLabel,
  ].join(' · ');
}

/// Choisit les nouveautés de « À la une » (au plus [count]) : films et
/// séries récents qui ont une image de fond, en alternant films et séries.
/// [movies] : derniers films ; [episodes] : derniers épisodes regroupés par
/// série (GET /Items/Latest).
List<HeroItem> pickHeroItems(
  List<Map<String, dynamic>> movies,
  List<Map<String, dynamic>> episodes, {
  int count = 5,
}) {
  final films = [
    for (final json in movies)
      if (json['Type'] == 'Movie') ItemDetails.fromJson(json),
  ].where((d) => d.backdropTag != null).toList();
  final series = <HeroItem>[];
  for (final json in episodes) {
    // Seules les séries renvoyées entières (plusieurs nouveaux épisodes)
    // ont leur résumé et leur image de fond
    if (json['Type'] != 'Series') continue;
    final details = ItemDetails.fromJson(json);
    if (details.backdropTag == null) continue;
    final newCount = (json['ChildCount'] as int?) ?? 1;
    series.add(
      HeroItem(
        details: details,
        eyebrow: newCount > 1
            ? '$newCount nouveaux épisodes'
            : 'Nouvel épisode',
      ),
    );
  }
  final picked = <HeroItem>[];
  var m = 0;
  var s = 0;
  while (picked.length < count && (m < films.length || s < series.length)) {
    // Film, série, film… (sauf s'il n'en reste que d'un genre)
    final takeFilm =
        s >= series.length || (m < films.length && picked.length.isEven);
    if (takeFilm) {
      picked.add(HeroItem(details: films[m++], eyebrow: 'Nouveau film'));
    } else {
      picked.add(series[s++]);
    }
  }
  return picked;
}

/// Une série qui a de nouveaux épisodes (rangée « Nouveaux épisodes »).
class NewEpisodesEntry {
  const NewEpisodesEntry({
    required this.series,
    required this.count,
    required this.label,
    this.seasonId,
  });

  /// Lit un élément de GET /Items/Latest (épisodes regroupés) : la série
  /// (plusieurs épisodes), une saison, ou un épisode seul.
  factory NewEpisodesEntry.fromLatestJson(Map<String, dynamic> json) {
    final type = json['Type'];
    final isSeries = type == 'Series';
    final imageTags = json['ImageTags'] as Map<String, dynamic>?;
    final count = (json['ChildCount'] as int?) ?? 1;
    final season = json['ParentIndexNumber'] as int?;
    final number = json['IndexNumber'] as int?;
    final series = MediaItem(
      id:
          (isSeries ? json['Id'] : json['SeriesId']) as String? ??
          json['Id'] as String,
      name:
          (isSeries ? json['Name'] : json['SeriesName']) as String? ??
          (json['Name'] as String?) ??
          'Sans titre',
      type: 'Series',
      posterTag: isSeries
          ? (imageTags?['Primary'] as String?)
          : (json['SeriesPrimaryImageTag'] as String?),
    );
    final String label;
    if (type == 'Episode' && season != null && number != null) {
      label = 'S$season · É$number';
    } else {
      label = count > 1 ? '$count nouveaux épisodes' : '1 nouvel épisode';
    }
    return NewEpisodesEntry(
      series: series,
      count: type == 'Episode' ? 1 : count,
      label: label,
      seasonId: switch (type) {
        'Season' => json['Id'] as String?,
        'Episode' => json['SeasonId'] as String?,
        _ => null,
      },
    );
  }

  /// La série (pour l'affiche et la fiche).
  final MediaItem series;

  /// Nombre de nouveaux épisodes.
  final int count;

  /// Petite ligne sous le titre : « 3 nouveaux épisodes », « S5 · É3 ».
  final String label;

  /// Saison sur laquelle ouvrir la fiche (null : la série entière).
  final String? seasonId;
}

/// « Épisode suivant », ou « Nouvel épisode » s'il a été ajouté au serveur
/// il y a moins de 14 jours.
String nextUpLabel(DateTime? added, DateTime now) =>
    added != null && now.difference(added) < const Duration(days: 14)
    ? 'Nouvel épisode'
    : 'Épisode suivant';

/// « Ajouté aujourd'hui », « Ajouté hier », « Ajouté il y a 3 jours »…
/// Au-delà d'une semaine (ou date inconnue) : l'année du film.
String addedLabel(DateTime? added, DateTime now, {int? year}) {
  if (added == null) return year?.toString() ?? '';
  final today = DateTime(now.year, now.month, now.day);
  final local = added.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'Ajouté aujourd\'hui';
  if (days == 1) return 'Ajouté hier';
  if (days < 7) return 'Ajouté il y a $days jours';
  return year?.toString() ?? '';
}

/// « Continuer à regarder » comme sur Netflix : les films et épisodes
/// commencés ([resume]) et le prochain épisode des séries en cours
/// ([nextUp]), du plus récent au plus ancien. Une série n'apparaît qu'une
/// fois (son épisode commencé passe avant l'épisode suivant), et seulement
/// si au moins un de ses épisodes a été vu.
/// [series] : où en est chaque série (part vue, dernière lecture).
List<ResumeEntry> mergeContinueWatching(
  List<ResumeEntry> resume,
  List<ResumeEntry> nextUp,
  Map<String, WatchProgress> series,
) {
  final seen = {for (final e in resume) e.seriesId ?? e.id};
  final all = [
    ...resume,
    for (final e in nextUp)
      if (!seen.contains(e.seriesId ?? e.id) && _started(series[e.seriesId])) e,
  ];
  DateTime? date(ResumeEntry e) =>
      e.isNext ? series[e.seriesId]?.lastPlayed : e.progress.lastPlayed;
  // Tri stable : à date égale (ou inconnue), l'ordre du serveur est gardé
  final indexed = [for (final (i, e) in all.indexed) (i, e)];
  indexed.sort((a, b) {
    final da = date(a.$2);
    final db = date(b.$2);
    if (da != null && db != null && da != db) return db.compareTo(da);
    if (da == null && db != null) return 1;
    if (da != null && db == null) return -1;
    return a.$1.compareTo(b.$1);
  });
  return [for (final (_, e) in indexed) e];
}

/// Vrai si au moins un épisode de la série a été vu (inconnu : on garde).
/// Jellyfin propose aussi l'épisode 1 de séries juste « effleurées »
/// (épisode lancé quelques secondes, ou retiré de Continuer à regarder).
bool _started(WatchProgress? series) =>
    series == null || series.played || series.percentage > 0;
