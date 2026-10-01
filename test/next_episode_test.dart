import 'package:amplyfin/models/download_info.dart';
import 'package:amplyfin/models/next_episode.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests de l'épisode suivant automatique
void main() {
  group('Moment de la carte « Épisode suivant »', () {
    const episode = Duration(minutes: 42);

    test('au début du générique de fin, s\'il est connu', () {
      expect(
        nextEpisodeTrigger(episode, outroStart: const Duration(minutes: 40)),
        const Duration(minutes: 40),
      );
    });

    test('30 s avant la fin sinon', () {
      expect(
        nextEpisodeTrigger(episode),
        const Duration(minutes: 41, seconds: 30),
      );
    });

    test('générique peu plausible ignoré', () {
      // Au début de l'épisode, ou collé à la toute fin
      expect(
        nextEpisodeTrigger(episode, outroStart: const Duration(minutes: 5)),
        const Duration(minutes: 41, seconds: 30),
      );
      expect(
        nextEpisodeTrigger(
          episode,
          outroStart: const Duration(minutes: 41, seconds: 59),
        ),
        const Duration(minutes: 41, seconds: 30),
      );
    });

    test('pas de carte tant que la durée est inconnue', () {
      expect(nextEpisodeTrigger(Duration.zero), isNull);
      expect(nextEpisodeTrigger(const Duration(seconds: 50)), isNull);
    });
  });

  group('Prochain épisode téléchargé', () {
    DownloadInfo episode(String id, int season, int number, {String? series}) =>
        DownloadInfo(
          itemId: id,
          name: id,
          mediaSourceId: id,
          isEpisode: true,
          seriesId: series ?? 'malcolm',
          seasonNumber: season,
          episodeNumber: number,
        );

    final downloads = [
      episode('s2e1', 2, 1),
      episode('s1e3', 1, 3),
      episode('s1e1', 1, 1),
      episode('autre', 1, 2, series: 'lost'),
      const DownloadInfo(itemId: 'film', name: 'Film', mediaSourceId: 'f'),
    ];

    test('le suivant de la même série, saison suivante comprise', () {
      expect(nextDownloaded(downloads, downloads[2])?.itemId, 's1e3');
      expect(nextDownloaded(downloads, downloads[1])?.itemId, 's2e1');
    });

    test('rien après le dernier, ni pour un film', () {
      expect(nextDownloaded(downloads, downloads[0]), isNull);
      expect(nextDownloaded(downloads, downloads[4]), isNull);
    });
  });

  group('Épisode suivant lu par le serveur', () {
    test('titres pour le lecteur, reprise s\'il est commencé', () {
      final next = NextEpisode.fromJson({
        'Id': 'e4',
        'Name': 'Le Retour',
        'SeriesName': 'Malcolm',
        'SeriesId': 'malcolm',
        'ParentIndexNumber': 2,
        'IndexNumber': 4,
        'UserData': {'PlaybackPositionTicks': 600000000},
      });
      expect(next.title, 'Malcolm');
      expect(next.subtitle, 'S2 · É4 · Le Retour');
      expect(next.seriesId, 'malcolm');
      expect(next.start, const Duration(minutes: 1));
    });

    test('pas commencé : au début', () {
      final next = NextEpisode.fromJson({'Id': 'e5', 'Name': 'Suite'});
      expect(next.start, Duration.zero);
    });
  });
}
