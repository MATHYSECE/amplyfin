import 'media_quality.dart';
import 'movie.dart';

/// La fiche complète d'un film : ce qu'affiche l'écran de détail.
class MovieDetails {
  const MovieDetails({
    required this.movie,
    this.overview,
    this.genres = const [],
    this.runtime,
    this.officialRating,
    this.communityRating,
    this.backdropTag,
    this.quality,
  });

  /// Lit la fiche à partir du JSON renvoyé par GET /Items/{id}.
  factory MovieDetails.fromJson(Map<String, dynamic> json) {
    final ticks = json['RunTimeTicks'] as int?;
    final backdropTags = json['BackdropImageTags'] as List<dynamic>?;
    return MovieDetails(
      movie: Movie.fromJson(json),
      overview: json['Overview'] as String?,
      genres: [for (final g in (json['Genres'] as List<dynamic>?) ?? []) '$g'],
      runtime: ticksToDuration(ticks),
      officialRating: json['OfficialRating'] as String?,
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      backdropTag: (backdropTags != null && backdropTags.isNotEmpty)
          ? backdropTags.first as String?
          : null,
      quality: MediaQuality.fromItemJson(json),
    );
  }

  /// Titre, année, affiche (les mêmes infos que dans la grille).
  final Movie movie;

  /// Résumé du film.
  final String? overview;

  /// Genres (Action, Comédie…).
  final List<String> genres;

  /// Durée du film.
  final Duration? runtime;

  /// Âge conseillé (ex. « PG-13 », « FR-12 »).
  final String? officialRating;

  /// Note des spectateurs, sur 10.
  final double? communityRating;

  /// Empreinte de l'image de fond, ou null s'il n'y en a pas.
  final String? backdropTag;

  /// Qualité technique du fichier (définition, HDR, son), si connue.
  final MediaQuality? quality;

  /// Durée lisible : « 2 h 04 », « 1 h » ou « 45 min ».
  String? get runtimeLabel {
    final d = runtime;
    if (d == null || d.inSeconds <= 0) return null;
    final totalMinutes = (d.inSeconds / 60).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '$minutes min';
    if (minutes == 0) return '$hours h';
    return '$hours h ${minutes.toString().padLeft(2, '0')}';
  }

  /// Note lisible à la française : « 7,8 ».
  String? get ratingLabel =>
      communityRating?.toStringAsFixed(1).replaceAll('.', ',');
}

/// Jellyfin compte les durées en « ticks » : 10 millions par seconde.
Duration? ticksToDuration(int? ticks) =>
    ticks == null ? null : Duration(microseconds: ticks ~/ 10);

/// L'inverse : une durée en « ticks » (pour les signalements au serveur).
int durationToTicks(Duration duration) => duration.inMicroseconds * 10;
