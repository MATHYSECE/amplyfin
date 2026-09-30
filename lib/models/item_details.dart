import 'durations.dart';
import 'media_item.dart';
import 'media_quality.dart';

/// La fiche complète d'un film ou d'une série : ce qu'affiche l'écran de détail.
class ItemDetails {
  const ItemDetails({
    required this.item,
    this.overview,
    this.genres = const [],
    this.runtime,
    this.officialRating,
    this.communityRating,
    this.backdropTag,
    this.quality,
    this.endYear,
    this.status,
  });

  /// Lit la fiche à partir du JSON renvoyé par GET /Items/{id}.
  factory ItemDetails.fromJson(Map<String, dynamic> json) {
    final ticks = json['RunTimeTicks'] as int?;
    final backdropTags = json['BackdropImageTags'] as List<dynamic>?;
    final endDate = json['EndDate'] as String?;
    return ItemDetails(
      item: MediaItem.fromJson(json),
      overview: json['Overview'] as String?,
      genres: [for (final g in (json['Genres'] as List<dynamic>?) ?? []) '$g'],
      runtime: ticksToDuration(ticks),
      officialRating: json['OfficialRating'] as String?,
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      backdropTag: (backdropTags != null && backdropTags.isNotEmpty)
          ? backdropTags.first as String?
          : null,
      quality: MediaQuality.fromItemJson(json),
      endYear: endDate == null ? null : DateTime.tryParse(endDate)?.year,
      status: json['Status'] as String?,
    );
  }

  /// Titre, année, affiche (les mêmes infos que dans la grille).
  final MediaItem item;

  /// Résumé.
  final String? overview;

  /// Genres (Action, Comédie…).
  final List<String> genres;

  /// Durée (films).
  final Duration? runtime;

  /// Âge conseillé (ex. « PG-13 », « FR-12 »).
  final String? officialRating;

  /// Note des spectateurs, sur 10.
  final double? communityRating;

  /// Empreinte de l'image de fond, ou null s'il n'y en a pas.
  final String? backdropTag;

  /// Qualité technique du fichier (films), si connue.
  final MediaQuality? quality;

  /// Année de fin (séries terminées).
  final int? endYear;

  /// État d'une série pour le serveur : « Continuing », « Ended »…
  final String? status;

  /// Durée lisible : « 2 h 04 », « 1 h » ou « 45 min ».
  String? get runtimeLabel => formatRuntime(runtime);

  /// Note lisible à la française : « 7,8 ».
  String? get ratingLabel =>
      communityRating?.toStringAsFixed(1).replaceAll('.', ',');

  /// Années d'une série : « 2008 – 2013 », ou juste « 2008 ».
  String? get yearsLabel {
    final start = item.year;
    if (start == null) return endYear?.toString();
    if (endYear == null || endYear == start) return '$start';
    return '$start – $endYear';
  }

  /// État d'une série, en français.
  String? get statusLabel => switch (status) {
    'Continuing' => 'En cours',
    'Ended' => 'Terminée',
    'Unreleased' => 'À venir',
    _ => null,
  };
}
