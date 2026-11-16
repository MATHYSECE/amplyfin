import 'search_results.dart';

/// Un genre (Action, Comédie…), avec son nombre de films et de séries.
class Genre {
  const Genre({
    required this.id,
    required this.name,
    this.movieCount = 0,
    this.seriesCount = 0,
  });

  /// Lit un genre renvoyé par GET /Genres (avec fields=ItemCounts).
  factory Genre.fromJson(Map<String, dynamic> json) => Genre(
    id: json['Id'] as String,
    name: (json['Name'] as String?) ?? 'Sans nom',
    movieCount: (json['MovieCount'] as int?) ?? 0,
    seriesCount: (json['SeriesCount'] as int?) ?? 0,
  );

  final String id;
  final String name;
  final int movieCount;
  final int seriesCount;

  /// Nombre de titres du [type] (« Movie », « Series »), ou des deux.
  int countFor(String? type) => switch (type) {
    'Movie' => movieCount,
    'Series' => seriesCount,
    _ => movieCount + seriesCount,
  };
}

/// Genres à proposer : ceux qui ont au moins [minCount] titres du [type]
/// (null : films et séries ensemble), dans l'ordre alphabétique à la
/// française (« Épouvante » rangé avec les E).
List<Genre> usableGenres(List<Genre> genres, {String? type, int minCount = 3}) {
  final kept = [
    for (final genre in genres)
      if (genre.countFor(type) >= minCount) genre,
  ];
  kept.sort(
    (a, b) => normalizeForSearch(a.name).compareTo(normalizeForSearch(b.name)),
  );
  return kept;
}

/// Tri d'une grille de films ou de séries.
enum LibrarySort {
  title('Titre (A → Z)', null),
  added('Ajoutés récemment', 'DateCreated'),
  year('Année de sortie', 'ProductionYear'),
  rating('Les mieux notés', 'CommunityRating');

  const LibrarySort(this.label, this.sortBy);

  final String label;

  /// Tri pour le serveur (null : par titre).
  final String? sortBy;

  /// Relit un tri enregistré (le titre par défaut).
  static LibrarySort fromName(String? name) =>
      values.where((s) => s.name == name).firstOrNull ?? title;
}
