import 'dart:convert';

import 'package:amplyfin/api/jellyfin_api.dart';
import 'package:amplyfin/models/episode.dart';
import 'package:amplyfin/models/item_details.dart';
import 'package:amplyfin/models/resume_entry.dart';
import 'package:amplyfin/models/watch_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Tests de la reprise de lecture
void main() {
  // 42 min 17 s, en « ticks » (10 millions par seconde)
  const positionTicks = (42 * 60 + 17) * 10000000;
  // 1 h 50, en « ticks »
  const runtimeTicks = 110 * 60 * 10000000;

  group('Où en est la lecture', () {
    test('lu dans « UserData »', () {
      final progress = WatchProgress.fromUserData({
        'PlaybackPositionTicks': positionTicks,
        'PlayedPercentage': 38.4,
        'Played': false,
      });
      expect(progress.position, const Duration(minutes: 42, seconds: 17));
      expect(progress.canResume, isTrue);
      expect(progress.fraction, closeTo(0.384, 0.0001));
      expect(progress.resumeLabel, 'Reprendre à 42:17');
      expect(
        progress.remainingLabel(const Duration(hours: 1, minutes: 50)),
        'Reste 1 h 08',
      );
    });

    test('rien de commencé', () {
      const empty = WatchProgress();
      expect(empty.canResume, isFalse);
      expect(WatchProgress.fromUserData(null).canResume, isFalse);
      expect(
        WatchProgress.fromUserData({'PlaybackPositionTicks': 0, 'Played': true})
            .played,
        isTrue,
      );
    });

    test('pourcentage hors limites ramené entre 0 et 1', () {
      expect(const WatchProgress(percentage: 140).fraction, 1);
      expect(const WatchProgress(percentage: -3).fraction, 0);
    });

    test('durée inconnue : pas de temps restant', () {
      const progress = WatchProgress(position: Duration(minutes: 5));
      expect(progress.remainingLabel(null), isNull);
    });
  });

  group('Fiches et épisodes', () {
    test('film commencé', () {
      final details = ItemDetails.fromJson({
        'Id': 'film',
        'Name': '1917',
        'RunTimeTicks': runtimeTicks,
        'UserData': {
          'PlaybackPositionTicks': positionTicks,
          'PlayedPercentage': 38.4,
        },
      });
      expect(details.progress.canResume, isTrue);
      expect(details.progress.resumeLabel, 'Reprendre à 42:17');
    });

    test('épisode commencé', () {
      final episode = Episode.fromJson({
        'Id': 'ep',
        'Name': 'Las Vegas',
        'UserData': {'PlaybackPositionTicks': positionTicks, 'Played': false},
      });
      expect(episode.progress.canResume, isTrue);
      expect(episode.played, isFalse);
    });
  });

  group('Rangée « Continuer à regarder »', () {
    test('épisode : affiche de la série et « S5 · É1 »', () {
      final entry = ResumeEntry.fromJson({
        'Id': 'ep1',
        'Name': 'Las Vegas',
        'Type': 'Episode',
        'SeriesId': 'malcolm',
        'SeriesName': 'Malcolm',
        'SeriesPrimaryImageTag': 'tag-serie',
        'SeasonId': 'saison5',
        'ParentIndexNumber': 5,
        'IndexNumber': 1,
        'RunTimeTicks': runtimeTicks,
        'UserData': {'PlaybackPositionTicks': positionTicks},
      });
      expect(entry.id, 'ep1');
      expect(entry.isEpisode, isTrue);
      expect(entry.poster.id, 'malcolm');
      expect(entry.poster.posterTag, 'tag-serie');
      expect(entry.seasonId, 'saison5');
      expect(entry.title, 'Malcolm');
      expect(entry.subtitle, 'S5 · É1');
      expect(entry.playerTitle, 'Malcolm');
      expect(entry.playerSubtitle, 'S5 · É1 · Las Vegas');
      expect(entry.remainingLabel, 'Reste 1 h 08');
    });

    test('film : son affiche et son année', () {
      final entry = ResumeEntry.fromJson({
        'Id': 'film',
        'Name': '1917',
        'Type': 'Movie',
        'ProductionYear': 2019,
        'ImageTags': {'Primary': 'tag-film'},
        'UserData': {'PlaybackPositionTicks': positionTicks},
      });
      expect(entry.isEpisode, isFalse);
      expect(entry.poster.id, 'film');
      expect(entry.poster.posterTag, 'tag-film');
      expect(entry.title, '1917');
      expect(entry.subtitle, '2019');
      expect(entry.playerSubtitle, isNull);
      expect(entry.progress.position, const Duration(minutes: 42, seconds: 17));
    });
  });

  group('Retirer de « Continuer à regarder »', () {
    test('position remise à 0 et « pas vu » envoyés au serveur', () async {
      late http.Request sent;
      await http.runWithClient(
        () =>
            JellyfinApi(
              serverUrl: 'http://serveur:8096',
              deviceId: 'appareil',
              token: 'jeton',
            ).updateWatchProgress(
              userId: 'moi',
              itemId: 'ep1',
              position: Duration.zero,
              played: false,
            ),
        () => MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
      );
      expect(sent.method, 'POST');
      expect(sent.url.path, '/UserItems/ep1/UserData');
      expect(sent.url.queryParameters['userId'], 'moi');
      expect(jsonDecode(sent.body), {
        'PlaybackPositionTicks': 0,
        'Played': false,
      });
    });

    test('« Annuler » remet la position précédente', () async {
      late http.Request sent;
      await http.runWithClient(
        () =>
            JellyfinApi(
              serverUrl: 'http://serveur:8096',
              deviceId: 'appareil',
              token: 'jeton',
            ).updateWatchProgress(
              userId: 'moi',
              itemId: 'film',
              position: const Duration(minutes: 42, seconds: 17),
              played: false,
            ),
        () => MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
      );
      expect(
        (jsonDecode(sent.body) as Map)['PlaybackPositionTicks'],
        positionTicks,
      );
    });
  });
}
