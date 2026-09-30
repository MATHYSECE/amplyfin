/// Un film de la bibliothèque, avec juste ce qu'il faut pour la grille.
class Movie {
  const Movie({
    required this.id,
    required this.name,
    this.year,
    this.posterTag,
  });

  /// Lit un film à partir du JSON renvoyé par GET /Items.
  factory Movie.fromJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] as Map<String, dynamic>?;
    return Movie(
      id: json['Id'] as String,
      name: (json['Name'] as String?) ?? 'Sans titre',
      year: json['ProductionYear'] as int?,
      posterTag: imageTags?['Primary'] as String?,
    );
  }

  /// Identifiant du film sur le serveur.
  final String id;

  /// Titre affiché.
  final String name;

  /// Année de sortie (peut manquer).
  final int? year;

  /// Empreinte de l'affiche : change quand l'affiche change sur le serveur.
  /// Null si le film n'a pas d'affiche.
  final String? posterTag;
}

/// Une « page » de films, et le nombre total de films sur le serveur.
class MoviePage {
  const MoviePage({required this.movies, required this.totalCount});

  final List<Movie> movies;
  final int totalCount;
}
