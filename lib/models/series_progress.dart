import 'episode.dart';
import 'season.dart';

/// L'épisode que propose le grand bouton d'une fiche de série.
class EpisodeToWatch {
  const EpisodeToWatch(this.episode, {required this.resume});

  final Episode episode;

  /// Vrai si l'épisode est commencé (le bouton dit « Reprendre »).
  final bool resume;

  /// Texte du bouton : « Reprendre S3 · É5 », « Lecture S1 · É1 ».
  String get label {
    final season = episode.seasonNumber;
    final number = episode.number;
    final verb = resume ? 'Reprendre' : 'Lecture';
    if (season == null || number == null) return verb;
    return '$verb S$season · É$number';
  }
}

/// Choisit l'épisode à regarder d'une série, d'après ses épisodes chargés
/// ([episodes] : identifiant de saison → épisodes) :
/// 1. l'épisode commencé le plus récemment ;
/// 2. sinon, celui qui suit le dernier épisode vu ;
/// 3. sinon (rien de vu, ou tout vu), le premier.
/// Les « Spéciaux » (saison 0) ne comptent que s'il n'y a rien d'autre.
/// Null si aucun épisode n'est chargé.
EpisodeToWatch? pickEpisodeToWatch(
  List<Season> seasons,
  Map<String, List<Episode>> episodes,
) {
  List<Episode> inOrder(Iterable<Season> seasons) => [
    for (final season in seasons) ...?episodes[season.id],
  ];
  var ordered = inOrder(seasons.where((s) => (s.number ?? 1) >= 1));
  if (ordered.isEmpty) ordered = inOrder(seasons);
  if (ordered.isEmpty) return null;

  // 1. Commencé, pas fini : le plus récent
  Episode? started;
  for (final episode in ordered) {
    if (!episode.progress.canResume || episode.played) continue;
    final date = episode.progress.lastPlayed;
    final best = started?.progress.lastPlayed;
    if (started == null ||
        (date != null && (best == null || date.isAfter(best)))) {
      started = episode;
    }
  }
  if (started != null) return EpisodeToWatch(started, resume: true);

  // 2. Le premier pas vu après le dernier vu
  final lastPlayed = ordered.lastIndexWhere((episode) => episode.played);
  if (lastPlayed >= 0) {
    final next = ordered.skip(lastPlayed + 1).where((e) => !e.played);
    if (next.isNotEmpty) return EpisodeToWatch(next.first, resume: false);
  }
  // 3. Le premier
  return EpisodeToWatch(ordered.first, resume: false);
}
