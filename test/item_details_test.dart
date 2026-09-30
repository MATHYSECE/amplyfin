import 'package:amplyfin/api/jellyfin_api.dart';
import 'package:amplyfin/models/durations.dart';
import 'package:amplyfin/models/item_details.dart';
import 'package:amplyfin/models/media_item.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests de la fiche d'un film : lecture du JSON, durée, note, image de fond
void main() {
  group('ItemDetails.fromJson', () {
    test('lit toutes les infos de la fiche', () {
      final details = ItemDetails.fromJson({
        'Id': 'abc123',
        'Name': 'Le Voyage de Chihiro',
        'ProductionYear': 2001,
        'ImageTags': {'Primary': 'tag42'},
        'Overview': 'Une petite fille dans un monde d\'esprits.',
        'Genres': ['Animation', 'Fantastique'],
        'RunTimeTicks': 74400000000, // 2 h 04
        'OfficialRating': 'FR-U',
        'CommunityRating': 8.5,
        'BackdropImageTags': ['fond1', 'fond2'],
      });
      expect(details.item.name, 'Le Voyage de Chihiro');
      expect(details.item.posterTag, 'tag42');
      expect(details.overview, 'Une petite fille dans un monde d\'esprits.');
      expect(details.genres, ['Animation', 'Fantastique']);
      expect(details.runtimeLabel, '2 h 04');
      expect(details.officialRating, 'FR-U');
      expect(details.ratingLabel, '8,5');
      expect(details.backdropTag, 'fond1');
    });

    test('accepte une fiche presque vide', () {
      final details = ItemDetails.fromJson({
        'Id': 'abc123',
        'BackdropImageTags': [],
      });
      expect(details.overview, isNull);
      expect(details.genres, isEmpty);
      expect(details.runtimeLabel, isNull);
      expect(details.ratingLabel, isNull);
      expect(details.backdropTag, isNull);
    });

    test('lit une note entière (7 → « 7,0 »)', () {
      final details = ItemDetails.fromJson({
        'Id': 'abc123',
        'CommunityRating': 7,
      });
      expect(details.ratingLabel, '7,0');
    });
  });

  group('runtimeLabel', () {
    String? label(Duration d) => ItemDetails(
      item: const MediaItem(id: 'x', name: 'x'),
      runtime: d,
    ).runtimeLabel;

    test('moins d\'une heure', () {
      expect(label(const Duration(minutes: 45)), '45 min');
    });

    test('heure pile', () {
      expect(label(const Duration(hours: 1)), '1 h');
    });

    test('heures et minutes, minutes sur deux chiffres', () {
      expect(label(const Duration(hours: 1, minutes: 5)), '1 h 05');
    });

    test('arrondit à la minute la plus proche', () {
      expect(label(const Duration(minutes: 89, seconds: 40)), '1 h 30');
    });
  });

  test('un tick = un dix-millionième de seconde', () {
    expect(ticksToDuration(10000000), const Duration(seconds: 1));
    expect(ticksToDuration(null), isNull);
  });

  group('backdropUrl', () {
    final api = JellyfinApi(serverUrl: 'http://serveur:8096', deviceId: 'test');

    test('construit l\'adresse de l\'image de fond', () {
      const details = ItemDetails(
        item: MediaItem(id: 'abc123', name: 'Film'),
        backdropTag: 'fond1',
      );
      expect(
        api.backdropUrl(details, width: 1200),
        'http://serveur:8096/Items/abc123/Images/Backdrop'
        '?fillWidth=1200&quality=90&tag=fond1',
      );
    });

    test('renvoie null sans image de fond', () {
      const details = ItemDetails(
        item: MediaItem(id: 'abc123', name: 'Film'),
      );
      expect(api.backdropUrl(details, width: 1200), isNull);
    });
  });
}
