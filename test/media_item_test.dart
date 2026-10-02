import 'package:amplyfin/api/jellyfin_api.dart';
import 'package:amplyfin/models/media_item.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests de la lecture d'un film et de l'adresse de son affiche
void main() {
  group('MediaItem.fromJson', () {
    test('lit titre, année et empreinte de l\'affiche', () {
      final movie = MediaItem.fromJson({
        'Id': 'abc123',
        'Name': 'Le Voyage de Chihiro',
        'ProductionYear': 2001,
        'ImageTags': {'Primary': 'tag42'},
      });
      expect(movie.id, 'abc123');
      expect(movie.name, 'Le Voyage de Chihiro');
      expect(movie.year, 2001);
      expect(movie.posterTag, 'tag42');
    });

    test('accepte un film sans année, sans titre ni affiche', () {
      final movie = MediaItem.fromJson({'Id': 'abc123'});
      expect(movie.name, 'Sans titre');
      expect(movie.year, isNull);
      expect(movie.posterTag, isNull);
      expect(movie.progress.played, isFalse);
    });

    test('vu ou pas, et épisodes pas vus d\'une série', () {
      final movie = MediaItem.fromJson({
        'Id': 'film1',
        'Type': 'Movie',
        'UserData': {'Played': true},
      });
      expect(movie.progress.played, isTrue);

      final series = MediaItem.fromJson({
        'Id': 'serie1',
        'Type': 'Series',
        'UserData': {'Played': false, 'UnplayedItemCount': 12},
      });
      expect(series.progress.played, isFalse);
      expect(series.progress.unplayedCount, 12);
    });
  });

  group('posterUrl', () {
    JellyfinApi api(String serverUrl) =>
        JellyfinApi(serverUrl: serverUrl, deviceId: 'test');

    test('construit l\'adresse de l\'affiche à la bonne taille', () {
      const movie = MediaItem(id: 'abc123', name: 'Film', posterTag: 'tag42');
      expect(
        api('http://192.168.1.10:8096').posterUrl(movie, width: 400),
        'http://192.168.1.10:8096/Items/abc123/Images/Primary'
        '?fillWidth=400&quality=90&tag=tag42',
      );
    });

    test('garde le chemin du serveur (ex. /jellyfin)', () {
      const movie = MediaItem(id: 'abc123', name: 'Film', posterTag: 'tag42');
      expect(
        api('https://maison.fr/jellyfin').posterUrl(movie, width: 300),
        startsWith('https://maison.fr/jellyfin/Items/abc123/Images/Primary?'),
      );
    });

    test('renvoie null si le film n\'a pas d\'affiche', () {
      const movie = MediaItem(id: 'abc123', name: 'Film');
      expect(api('http://serveur:8096').posterUrl(movie, width: 400), isNull);
    });
  });
}
