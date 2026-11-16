import 'package:amplyfin/models/recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _category(String type, String? name, int count) => {
  'RecommendationType': type,
  'BaselineItemName': name,
  'Items': [
    for (var i = 0; i < count; i++)
      {'Id': '$type-$i', 'Name': 'Film $i', 'Type': 'Movie'},
  ],
};

void main() {
  test('titres des rangées', () {
    String? title(String type) =>
        Recommendation.fromJson(_category(type, 'Dune', 1))?.title;
    expect(title('SimilarToRecentlyPlayed'), 'Parce que tu as regardé Dune');
    expect(title('SimilarToLikedItem'), 'Parce que tu aimes Dune');
    expect(title('HasLikedDirector'), 'Réalisés par Dune');
    expect(title('HasActorFromRecentlyPlayed'), 'Avec Dune');
    expect(title('Autre'), isNull);
  });

  test('catégorie vide ou sans nom : ignorée', () {
    expect(
      Recommendation.fromJson(_category('SimilarToLikedItem', 'Dune', 0)),
      isNull,
    );
    expect(
      Recommendation.fromJson(_category('SimilarToLikedItem', null, 3)),
      isNull,
    );
  });

  test('au plus deux rangées, assez remplies, sans doublon', () {
    final rows = [
      Recommendation.fromJson(_category('SimilarToLikedItem', 'Dune', 2))!,
      Recommendation.fromJson(_category('SimilarToLikedItem', 'Tenet', 6))!,
      Recommendation.fromJson(_category('SimilarToLikedItem', 'Tenet', 8))!,
      Recommendation.fromJson(_category('HasLikedActor', 'Omar Sy', 5))!,
      Recommendation.fromJson(_category('HasLikedActor', 'Brad Pitt', 5))!,
    ];
    final picked = pickRecommendations(rows);
    expect(picked.map((row) => row.title), [
      'Parce que tu aimes Tenet',
      'Avec Omar Sy',
    ]);
    expect(picked.first.items, hasLength(6));
  });
}
