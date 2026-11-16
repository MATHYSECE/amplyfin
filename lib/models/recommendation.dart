import 'media_item.dart';

/// Une rangée de films conseillés par le serveur, d'après ce qui a été
/// regardé ou mis dans « Ma liste » (GET /Movies/Recommendations).
class Recommendation {
  const Recommendation({required this.title, required this.items});

  /// Lit une catégorie du serveur. Null si elle est vide ou d'un type
  /// inconnu.
  static Recommendation? fromJson(Map<String, dynamic> json) {
    final name = (json['BaselineItemName'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    final title = switch (json['RecommendationType']) {
      'SimilarToRecentlyPlayed' => 'Parce que tu as regardé $name',
      'SimilarToLikedItem' => 'Parce que tu aimes $name',
      'HasDirectorFromRecentlyPlayed' ||
      'HasLikedDirector' => 'Réalisés par $name',
      'HasActorFromRecentlyPlayed' || 'HasLikedActor' => 'Avec $name',
      _ => null,
    };
    if (title == null) return null;
    final items = [
      for (final item in (json['Items'] as List<dynamic>?) ?? const [])
        if (item is Map<String, dynamic> && item['Id'] is String)
          MediaItem.fromJson(item),
    ];
    if (items.isEmpty) return null;
    return Recommendation(title: title, items: items);
  }

  /// Titre de la rangée : « Parce que tu as regardé Dune ».
  final String title;
  final List<MediaItem> items;
}

/// Garde au plus [max] rangées qui valent le coup : au moins [minItems]
/// films, et jamais deux fois le même titre de rangée.
List<Recommendation> pickRecommendations(
  List<Recommendation> all, {
  int max = 2,
  int minItems = 4,
}) {
  final titles = <String>{};
  return [
    for (final row in all)
      if (row.items.length >= minItems && titles.add(row.title)) row,
  ].take(max).toList();
}
