import 'package:amplyfin/api/jellyfin_api.dart';
import 'package:amplyfin/models/episode.dart';
import 'package:amplyfin/models/item_details.dart';
import 'package:amplyfin/models/media_item.dart';
import 'package:amplyfin/models/season.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests des séries : fiche, saisons, épisodes
void main() {
  group('Fiche d\'une série', () {
    test('série terminée : années de début et de fin', () {
      final details = ItemDetails.fromJson({
        'Id': 'serie1',
        'Name': 'Breaking Bad',
        'Type': 'Series',
        'ProductionYear': 2008,
        'EndDate': '2013-09-29T00:00:00.0000000Z',
        'Status': 'Ended',
      });
      expect(details.item.isSeries, isTrue);
      expect(details.yearsLabel, '2008 – 2013');
      expect(details.statusLabel, 'Terminée');
    });

    test('série en cours : juste l\'année de début', () {
      final details = ItemDetails.fromJson({
        'Id': 'serie1',
        'ProductionYear': 2022,
        'Status': 'Continuing',
      });
      expect(details.yearsLabel, '2022');
      expect(details.statusLabel, 'En cours');
    });

    test('un film n\'est pas une série', () {
      final item = MediaItem.fromJson({'Id': 'film1', 'Type': 'Movie'});
      expect(item.isSeries, isFalse);
    });
  });

  group('Season.fromJson', () {
    test('lit le nom et le numéro', () {
      final season = Season.fromJson({
        'Id': 'saison1',
        'Name': 'Saison 1',
        'IndexNumber': 1,
      });
      expect(season.name, 'Saison 1');
      expect(season.number, 1);
    });

    test('nom manquant : « Saison N »', () {
      final season = Season.fromJson({'Id': 'saison2', 'IndexNumber': 2});
      expect(season.name, 'Saison 2');
    });
  });

  group('Episode.fromJson', () {
    final episode = Episode.fromJson({
      'Id': 'ep3',
      'Name': 'La Poudre et la Toile',
      'SeriesName': 'Breaking Bad',
      'ParentIndexNumber': 1,
      'IndexNumber': 3,
      'Overview': 'Walt doit se débarrasser d\'un problème.',
      'RunTimeTicks': 28200000000, // 47 min
      'ImageTags': {'Primary': 'vignette1'},
      'UserData': {'Played': true},
    });

    test('lit toutes les infos', () {
      expect(episode.seasonNumber, 1);
      expect(episode.number, 3);
      expect(episode.runtimeLabel, '47 min');
      expect(episode.imageTag, 'vignette1');
      expect(episode.played, isTrue);
    });

    test('titres : liste et lecteur', () {
      expect(episode.listTitle, '3. La Poudre et la Toile');
      expect(episode.code, 'S1E3');
      expect(episode.playerTitle, 'Breaking Bad');
      expect(episode.playerSubtitle, 'S1 · É3 · La Poudre et la Toile');
    });

    test('ligne d\'infos : durée puis qualité', () {
      final withQuality = Episode.fromJson({
        'Id': 'ep1',
        'Name': 'Pilote',
        'RunTimeTicks': 13200000000, // 22 min
        'MediaStreams': [
          {'Type': 'Video', 'Codec': 'hevc', 'Width': 1920, 'Height': 1080},
          {'Type': 'Audio', 'Codec': 'eac3', 'Channels': 2},
        ],
      });
      expect(withQuality.infoLine, '22 min · 1080p · HEVC · E-AC3 Stéréo');
    });

    test('épisode sans numéro ni série : titre seul', () {
      final bare = Episode.fromJson({'Id': 'ep', 'Name': 'Bonus'});
      expect(bare.listTitle, 'Bonus');
      expect(bare.playerTitle, 'Bonus');
      expect(bare.playerSubtitle, isNull);
      expect(bare.played, isFalse);
    });

    test('adresse de la vignette', () {
      final api = JellyfinApi(serverUrl: 'http://serveur:8096', deviceId: 't');
      expect(
        api.episodeImageUrl(episode, width: 400),
        'http://serveur:8096/Items/ep3/Images/Primary'
        '?fillWidth=400&quality=90&tag=vignette1',
      );
    });
  });
}
