import 'package:amplyfin/models/download_info.dart';
import 'package:amplyfin/models/watch_progress.dart';
import 'package:amplyfin/services/download_groups.dart';
import 'package:amplyfin/services/offline_progress.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests du mode hors ligne
void main() {
  final now = DateTime.utc(2026, 10, 1, 20);
  const film = Duration(minutes: 100);

  group('Position gardée sur le téléphone', () {
    test('en cours de film : position retenue, à envoyer', () {
      final saved = SavedProgress.fromPlayback(
        position: const Duration(minutes: 42),
        runtime: film,
        now: now,
      );
      expect(saved.position, const Duration(minutes: 42));
      expect(saved.played, isFalse);
      expect(saved.pending, isTrue);
      expect(saved.resumePosition, const Duration(minutes: 42));
      expect(saved.fraction, closeTo(0.42, 0.001));
    });

    test('comme le serveur : sous 5 % rien, au-delà de 90 % « vu »', () {
      final start = SavedProgress.fromPlayback(
        position: const Duration(minutes: 3),
        runtime: film,
        now: now,
      );
      expect(start.position, Duration.zero);
      expect(start.played, isFalse);

      final end = SavedProgress.fromPlayback(
        position: const Duration(minutes: 95),
        runtime: film,
        now: now,
      );
      expect(end.played, isTrue);
      expect(end.resumePosition, Duration.zero);
      expect(end.toWatchProgress().played, isTrue);
    });

    test('durée inconnue : position gardée telle quelle', () {
      final saved = SavedProgress.fromPlayback(
        position: const Duration(minutes: 2),
        now: now,
      );
      expect(saved.position, const Duration(minutes: 2));
      expect(saved.fraction, 0);
    });

    test('enregistrée puis relue à l\'identique', () {
      final saved = SavedProgress.fromPlayback(
        position: const Duration(minutes: 42),
        runtime: film,
        now: now,
      );
      final copy = SavedProgress.fromJson(saved.toJson());
      expect(copy.toJson(), saved.toJson());
      expect(copy.updatedAt, now);
      expect(copy.sent().pending, isFalse);
    });

    test('pour la fiche, comme si elle venait du serveur', () {
      final progress = SavedProgress.fromPlayback(
        position: const Duration(minutes: 42),
        runtime: film,
        now: now,
      ).toWatchProgress();
      expect(progress.canResume, isTrue);
      expect(progress.position, const Duration(minutes: 42));
      expect(progress.fraction, closeTo(0.42, 0.001));
      expect(progress.lastPlayed, now);
    });
  });

  group('La plus récente gagne', () {
    final phone = SavedProgress.fromPlayback(
      position: const Duration(minutes: 42),
      runtime: film,
      now: now,
    );

    test('jamais lu ailleurs, ou plus tôt : le téléphone', () {
      expect(phoneIsNewer(phone, null), isTrue);
      expect(
        phoneIsNewer(phone, now.subtract(const Duration(hours: 1))),
        isTrue,
      );
      // Même moment (position déjà envoyée) : rien ne change
      expect(phoneIsNewer(phone, now), isTrue);
    });

    test('lu plus tard sur un autre appareil : le serveur', () {
      expect(phoneIsNewer(phone, now.add(const Duration(minutes: 5))), isFalse);
    });

    test('position du serveur gardée telle quelle', () {
      final later = now.add(const Duration(hours: 2));
      final saved = SavedProgress.fromServer(
        WatchProgress(
          position: const Duration(minutes: 70),
          percentage: 70,
          lastPlayed: later,
        ),
        runtime: film,
        now: now,
      );
      expect(saved.position, const Duration(minutes: 70));
      expect(saved.updatedAt, later);
      expect(saved.pending, isFalse);
    });

    test('date de dernière lecture lue dans la réponse du serveur', () {
      final progress = WatchProgress.fromUserData({
        'PlaybackPositionTicks': 42 * 60 * 10000000,
        'LastPlayedDate': '2026-10-01T21:30:00.0000000Z',
      });
      expect(progress.lastPlayed, DateTime.utc(2026, 10, 1, 21, 30));
      expect(WatchProgress.fromUserData({}).lastPlayed, isNull);
    });
  });

  group('Fiche sans le serveur', () {
    test('depuis les infos gardées avec le téléchargement', () {
      final info = DownloadInfo.fromItemJson({
        'Id': 'film',
        'Name': '1917',
        'Type': 'Movie',
        'ProductionYear': 2019,
        'Overview': 'Deux soldats portent un message.',
        'RunTimeTicks': 119 * 60 * 10000000,
        'ImageTags': {'Primary': 'tag-film'},
        'MediaSources': [
          {
            'Id': 'source',
            'Size': 12400000000,
            'DefaultAudioStreamIndex': 1,
            'MediaStreams': [
              {'Type': 'Video', 'Index': 0, 'Codec': 'hevc', 'Width': 3840},
              {'Type': 'Audio', 'Index': 1, 'Language': 'fre', 'Codec': 'eac3'},
            ],
          },
        ],
      });
      final details = info.toItemDetails(
        progress: const WatchProgress(position: Duration(minutes: 42)),
      );
      expect(details.item.name, '1917');
      expect(details.item.year, 2019);
      expect(details.overview, 'Deux soldats portent un message.');
      expect(details.runtimeLabel, '1 h 59');
      expect(details.audioTracks.single.index, 1);
      expect(details.defaultAudioIndex, 1);
      expect(details.fileSize, 12400000000);
      expect(details.quality, isNotNull);
      expect(details.progress.canResume, isTrue);
    });
  });

  group("Fiche d'une série sans le serveur", () {
    DownloadInfo episode(
      String id,
      int season,
      int number, {
      bool full = false,
    }) {
      final info = DownloadInfo.fromItemJson({
        'Id': id,
        'Name': 'Épisode $number',
        'Type': 'Episode',
        'SeriesId': 'malcolm',
        'SeriesName': 'Malcolm',
        'SeasonId': 'saison$season',
        'ParentIndexNumber': season,
        'IndexNumber': number,
        'ProductionYear': 2004,
      });
      // Téléchargement récent : avec les infos de la série
      return full
          ? info.withSeries({
              'Overview': 'Un ado surdoué dans une famille bruyante.',
              'ProductionYear': 2000,
              'EndDate': '2006-05-14T00:00:00.0000000Z',
              'Status': 'Ended',
            })
          : info;
    }

    test("saisons et épisodes téléchargés seulement, dans l'ordre", () {
      final offline = OfflineSeries.of([
        episode('e52', 5, 2),
        episode('e41', 4, 1, full: true),
        episode('e51', 5, 1),
      ]);
      expect(offline.seasons.map((s) => s.name), ['Saison 4', 'Saison 5']);
      expect(offline.seasons.first.id, 'saison4');
      expect(offline.episodes['saison5']!.map((e) => e.id), ['e51', 'e52']);
      expect(offline.episodes['saison5']!.first.listTitle, '1. Épisode 1');
    });

    test("infos de la série reprises d'un épisode qui les a", () {
      final details = OfflineSeries.of([
        episode('e51', 5, 1),
        episode('e41', 4, 1, full: true),
      ]).details;
      expect(details.item.name, 'Malcolm');
      expect(details.item.isSeries, isTrue);
      expect(details.overview, 'Un ado surdoué dans une famille bruyante.');
      expect(details.yearsLabel, '2000 – 2006');
      expect(details.statusLabel, 'Terminée');
    });

    test('ancien téléchargement : fiche quand même, sans résumé', () {
      final details = OfflineSeries.of([episode('e51', 5, 1)]).details;
      expect(details.item.name, 'Malcolm');
      expect(details.overview, isNull);
      // L'année de l'épisode n'est pas celle de la série
      expect(details.item.year, isNull);
    });

    test('position de lecture reprise pour chaque épisode', () {
      final offline = OfflineSeries.of(
        [episode('e51', 5, 1)],
        progressOf: (id) =>
            const WatchProgress(position: Duration(minutes: 12)),
      );
      expect(offline.episodes['saison5']!.single.progress.canResume, isTrue);
    });

    test('infos de la série gardées avec le téléchargement', () {
      final info = episode('e41', 4, 1, full: true);
      final copy = DownloadInfo.fromJson(info.toJson());
      expect(copy.seriesOverview, info.seriesOverview);
      expect(copy.seriesYear, 2000);
      expect(copy.seriesEndYear, 2006);
      expect(copy.seriesStatus, 'Ended');
    });
  });
}
