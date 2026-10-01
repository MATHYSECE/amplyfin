import 'package:amplyfin/models/download_info.dart';
import 'package:amplyfin/models/search_results.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests de la recherche
void main() {
  group('Texte simplifié', () {
    test('sans accents, majuscules ni espaces en trop', () {
      expect(normalizeForSearch('  École  du   Crime '), 'ecole du crime');
      expect(normalizeForSearch('Œuvre Ça'), 'oeuvre ca');
      expect(normalizeForSearch('À couteaux tirés'), 'a couteaux tires');
    });
  });

  group('Recherches récentes', () {
    test('la nouvelle en tête, sans doublon', () {
      expect(addToHistory(['dune', 'malcolm'], 'Malcolm'), ['Malcolm', 'dune']);
      expect(addToHistory(['dune'], '  1917  '), ['1917', 'dune']);
      // Accents : même recherche
      expect(addToHistory(['ecole'], 'École'), ['École']);
    });

    test('10 au plus, rien de vide', () {
      final many = [for (var i = 0; i < 10; i++) 'film $i'];
      final updated = addToHistory(many, 'nouveau');
      expect(updated.length, 10);
      expect(updated.first, 'nouveau');
      expect(updated.last, 'film 8');
      expect(addToHistory(['dune'], '   '), ['dune']);
    });
  });

  group('Résultats du serveur', () {
    test('épisode : sa série, sa saison et « S5 · É1 · Titre »', () {
      final episode = SearchEpisode.fromJson({
        'Id': 'ep',
        'Name': 'Las Vegas',
        'Type': 'Episode',
        'SeriesId': 'malcolm',
        'SeriesName': 'Malcolm',
        'SeriesPrimaryImageTag': 'tag-serie',
        'SeasonId': 'saison5',
        'ParentIndexNumber': 5,
        'IndexNumber': 1,
        'ImageTags': {'Primary': 'tag-vignette'},
      });
      expect(episode.series.id, 'malcolm');
      expect(episode.series.isSeries, isTrue);
      expect(episode.series.posterTag, 'tag-serie');
      expect(episode.seasonId, 'saison5');
      expect(episode.detail, 'S5 · É1 · Las Vegas');
      expect(episode.imageTag, 'tag-vignette');
    });

    test('personne : initiales à la place de la photo', () {
      expect(
        SearchPerson.fromJson({'Id': 'p', 'Name': 'Tom Hanks'}).initials,
        'TH',
      );
      expect(
        SearchPerson.fromJson({'Id': 'p', 'Name': 'Zendaya'}).initials,
        'Z',
      );
    });

    test('rien trouvé', () {
      expect(const SearchResults().isEmpty, isTrue);
    });
  });

  group('Hors ligne : dans les téléchargements', () {
    DownloadInfo movie(String id, String name) =>
        DownloadInfo(itemId: id, name: name, mediaSourceId: id);
    DownloadInfo episode(String id, String name, int number) => DownloadInfo(
      itemId: id,
      name: name,
      mediaSourceId: id,
      isEpisode: true,
      seriesId: 'malcolm',
      seriesName: 'Malcolm',
      seasonNumber: 5,
      episodeNumber: number,
      seasonId: 'saison5',
    );
    final downloaded = [
      movie('couteaux', 'À couteaux tirés'),
      movie('1917', '1917'),
      episode('e1', 'Las Vegas', 1),
      episode('e2', 'Malcolm fait du cinéma', 2),
    ];

    test('films par titre, sans accents ni majuscules', () {
      final results = searchDownloads(downloaded, 'COUTEAUX TIRES');
      expect(results.movies.map((m) => m.id), ['couteaux']);
      expect(results.series, isEmpty);
    });

    test('série une seule fois, épisodes par titre', () {
      final results = searchDownloads(downloaded, 'malcolm');
      expect(results.series.map((s) => s.id), ['malcolm']);
      // « Malcolm fait du cinéma » : le titre de l'épisode correspond aussi
      expect(results.episodes.map((e) => e.id), ['e2']);
      expect(results.episodes.single.seasonId, 'saison5');
    });

    test('rien trouvé, ou recherche vide', () {
      expect(searchDownloads(downloaded, 'dune').isEmpty, isTrue);
      expect(searchDownloads(downloaded, '  ').isEmpty, isTrue);
    });
  });
}
