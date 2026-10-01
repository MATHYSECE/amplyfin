import 'package:amplyfin/models/genre.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests des catégories (genres) et du tri des grilles
void main() {
  group('Genres', () {
    test('lus avec leur nombre de films et de séries', () {
      final genre = Genre.fromJson({
        'Id': 'g1',
        'Name': 'Comédie',
        'MovieCount': 12,
        'SeriesCount': 4,
      });
      expect(genre.name, 'Comédie');
      expect(genre.countFor('Movie'), 12);
      expect(genre.countFor('Series'), 4);
      expect(genre.countFor(null), 16);
      expect(Genre.fromJson({'Id': 'g2'}).countFor(null), 0);
    });

    const genres = [
      Genre(id: 'f', name: 'Fantastique', movieCount: 5, seriesCount: 1),
      Genre(id: 'e', name: 'Épouvante', movieCount: 8),
      Genre(id: 'd', name: 'Drame', movieCount: 20, seriesCount: 9),
      Genre(id: 'w', name: 'Western', movieCount: 2),
      Genre(id: 's', name: 'Sci-Fi & Fantasy', seriesCount: 6),
    ];

    test('ordre alphabétique à la française (É avec les E)', () {
      expect(usableGenres(genres).map((g) => g.name), [
        'Drame',
        'Épouvante',
        'Fantastique',
        'Sci-Fi & Fantasy',
      ]);
    });

    test('genres trop petits (moins de 3 titres du type) écartés', () {
      expect(usableGenres(genres, type: 'Movie').map((g) => g.id), [
        'd',
        'e',
        'f',
      ]);
      expect(usableGenres(genres, type: 'Series').map((g) => g.id), ['d', 's']);
    });
  });

  group('Images des genres', () {
    test('jamais le même titre sur deux genres', () {
      final covers = pickDistinctCovers({
        'action': ['jump', 'heat', 'rambo'],
        'comedie': ['jump', 'heat'],
        'crime': ['jump'],
      }, (id) => id);
      // Crime n'a qu'un choix : il passe en premier
      expect(covers, {'crime': 'jump', 'comedie': 'heat', 'action': 'rambo'});
    });

    test('genre sans image, ou tous ses titres déjà pris', () {
      final covers = pickDistinctCovers({
        'vide': <String>[],
        'a': ['x'],
        'b': ['x'],
      }, (id) => id);
      expect(covers.containsKey('vide'), isFalse);
      expect(covers['a'], 'x');
      expect(covers['b'], 'x');
    });
  });

  group('Tri des grilles', () {
    test('choix retenu, titre par défaut', () {
      expect(LibrarySort.fromName('rating'), LibrarySort.rating);
      expect(LibrarySort.fromName(null), LibrarySort.title);
      expect(LibrarySort.fromName('inconnu'), LibrarySort.title);
    });

    test('tri demandé au serveur', () {
      expect(LibrarySort.title.sortBy, isNull);
      expect(LibrarySort.added.sortBy, 'DateCreated');
      expect(LibrarySort.year.sortBy, 'ProductionYear');
      expect(LibrarySort.rating.sortBy, 'CommunityRating');
    });
  });
}
