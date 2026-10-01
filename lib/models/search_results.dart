import 'download_info.dart';
import 'media_item.dart';

/// Un épisode trouvé : de quoi l'afficher et ouvrir la fiche de sa série
/// sur la bonne saison.
class SearchEpisode {
  const SearchEpisode({
    required this.id,
    required this.name,
    required this.series,
    this.seasonId,
    this.seasonNumber,
    this.number,
    this.imageTag,
  });

  /// Lit un épisode renvoyé par GET /Items.
  factory SearchEpisode.fromJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] as Map<String, dynamic>?;
    return SearchEpisode(
      id: json['Id'] as String,
      name: (json['Name'] as String?) ?? 'Sans titre',
      series: MediaItem(
        id: (json['SeriesId'] as String?) ?? json['Id'] as String,
        name: (json['SeriesName'] as String?) ?? 'Série',
        type: 'Series',
        posterTag: json['SeriesPrimaryImageTag'] as String?,
      ),
      seasonId: json['SeasonId'] as String?,
      seasonNumber: json['ParentIndexNumber'] as int?,
      number: json['IndexNumber'] as int?,
      imageTag: imageTags?['Primary'] as String?,
    );
  }

  /// Épisode téléchargé (recherche hors ligne).
  factory SearchEpisode.fromDownload(DownloadInfo info) => SearchEpisode(
    id: info.itemId,
    name: info.name,
    series: info.posterItem,
    seasonId: info.seasonId,
    seasonNumber: info.seasonNumber,
    number: info.episodeNumber,
    imageTag: info.imageTag,
  );

  final String id;
  final String name;

  /// La série (pour son nom, son affiche et sa fiche).
  final MediaItem series;
  final String? seasonId;
  final int? seasonNumber;
  final int? number;

  /// Empreinte de la vignette de l'épisode (null s'il n'y en a pas).
  final String? imageTag;

  /// « S5 · É1 · Las Vegas ».
  String get detail {
    final code = (seasonNumber != null && number != null)
        ? 'S$seasonNumber · É$number'
        : null;
    return [?code, name].join(' · ');
  }
}

/// Un acteur, réalisateur… trouvé.
class SearchPerson {
  const SearchPerson({required this.id, required this.name, this.imageTag});

  factory SearchPerson.fromJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] as Map<String, dynamic>?;
    return SearchPerson(
      id: json['Id'] as String,
      name: (json['Name'] as String?) ?? 'Sans nom',
      imageTag: imageTags?['Primary'] as String?,
    );
  }

  final String id;
  final String name;

  /// Empreinte de la photo (null s'il n'y en a pas).
  final String? imageTag;

  /// Initiales, à la place de la photo : « TH » pour Tom Hanks.
  String get initials => name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
}

/// Résultats d'une recherche, rangés par type.
class SearchResults {
  const SearchResults({
    this.movies = const [],
    this.series = const [],
    this.episodes = const [],
    this.people = const [],
  });

  final List<MediaItem> movies;
  final List<MediaItem> series;
  final List<SearchEpisode> episodes;
  final List<SearchPerson> people;

  bool get isEmpty =>
      movies.isEmpty && series.isEmpty && episodes.isEmpty && people.isEmpty;
}

/// Texte simplifié pour comparer : minuscules, sans accents ni espaces en
/// trop (« École » et « ecole » sont pareils).
String normalizeForSearch(String text) {
  const accents = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'ã': 'a',
    'å': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'í': 'i',
    'ì': 'i',
    'ô': 'o',
    'ö': 'o',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'ÿ': 'y',
    'ñ': 'n',
    'œ': 'oe',
    'æ': 'ae',
  };
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    buffer.write(accents[char] ?? char);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Recherche hors ligne, dans les téléchargements terminés ([downloaded]) :
/// films par titre, séries par nom, épisodes par titre.
SearchResults searchDownloads(List<DownloadInfo> downloaded, String term) {
  final wanted = normalizeForSearch(term);
  if (wanted.isEmpty) return const SearchResults();
  bool matches(String? text) =>
      text != null && normalizeForSearch(text).contains(wanted);

  final movies = <MediaItem>[];
  final series = <String, MediaItem>{};
  final episodes = <SearchEpisode>[];
  for (final info in downloaded) {
    if (!info.isEpisode) {
      if (matches(info.name)) movies.add(info.posterItem);
      continue;
    }
    if (matches(info.seriesName)) {
      series.putIfAbsent(info.posterItem.id, () => info.posterItem);
    }
    if (matches(info.name)) episodes.add(SearchEpisode.fromDownload(info));
  }
  return SearchResults(
    movies: movies,
    series: series.values.toList(),
    episodes: episodes,
  );
}

/// Recherches récentes après une nouvelle recherche [term] : en tête de
/// liste, sans doublon (majuscules et accents comptent pareil), [max] au
/// plus.
List<String> addToHistory(List<String> history, String term, {int max = 10}) {
  final clean = term.trim();
  if (clean.isEmpty) return history;
  final key = normalizeForSearch(clean);
  return [
    clean,
    for (final old in history)
      if (normalizeForSearch(old) != key) old,
  ].take(max).toList();
}
