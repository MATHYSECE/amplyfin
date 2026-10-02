import 'package:amplyfin/models/server_admin.dart';
import 'package:amplyfin/models/user_settings.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests des réglages du compte et des données d'administration
void main() {
  group('UserSettings', () {
    final me = {
      'Name': 'admin',
      'Policy': {'IsAdministrator': true},
      'Configuration': {
        'AudioLanguagePreference': 'fra',
        'SubtitleLanguagePreference': '',
        'SubtitleMode': 'Smart',
        'PlayDefaultAudioTrack': true,
        'HidePlayedInLatest': true,
      },
    };

    test('lit langues, mode des sous-titres et droits', () {
      final settings = UserSettings.fromMe(me);
      // « fra » et « fre » : le même code partout dans l'appli
      expect(settings.audioLanguage, 'fre');
      expect(settings.subtitleLanguage, isNull);
      expect(settings.subtitleMode, SubtitleMode.smart);
      expect(settings.isAdmin, isTrue);
    });

    test('renvoie tous les réglages, avec les changements', () {
      final updated = UserSettings.fromMe(me)
          .copyWith(subtitleLanguage: 'eng', subtitleMode: SubtitleMode.always);
      final configuration = updated.toConfiguration();
      // Les autres réglages du compte ne sont pas perdus
      expect(configuration['HidePlayedInLatest'], isTrue);
      expect(configuration['SubtitleLanguagePreference'], 'eng');
      expect(configuration['SubtitleMode'], 'Always');
      // Langue audio choisie : elle passe avant la piste « par défaut »
      expect(configuration['AudioLanguagePreference'], 'fre');
      expect(configuration['PlayDefaultAudioTrack'], isFalse);
    });

    test('langue d\'origine : piste par défaut du fichier', () {
      final configuration = UserSettings.fromMe(me)
          .copyWith(clearAudio: true)
          .toConfiguration();
      expect(configuration['AudioLanguagePreference'], '');
      expect(configuration['PlayDefaultAudioTrack'], isTrue);
    });

    test('compte simple, réglages absents', () {
      final settings = UserSettings.fromMe({'Name': 'invite'});
      expect(settings.isAdmin, isFalse);
      expect(settings.subtitleMode, SubtitleMode.standard);
    });
  });

  group('Administration', () {
    test('lecture en cours avec conversion', () {
      final session = ActiveSession.fromJson({
        'UserName': 'admin',
        'DeviceName': 'iPhone',
        'Client': 'Amplyfin',
        'NowPlayingItem': {
          'Name': 'Maître et apprentie',
          'SeriesName': 'Ahsoka',
          'ParentIndexNumber': 1,
          'IndexNumber': 1,
          'RunTimeTicks': 33000000000,
        },
        'PlayState': {
          'PositionTicks': 16500000000,
          'IsPaused': false,
          'PlayMethod': 'Transcode',
        },
        'TranscodingInfo': {
          'IsVideoDirect': true,
          'IsAudioDirect': false,
          'AudioCodec': 'aac',
        },
      })!;
      expect(session.title, 'Ahsoka');
      expect(session.subtitle, 'S1 · É1 · Maître et apprentie');
      expect(session.device, 'iPhone · Amplyfin');
      expect(session.fraction, closeTo(0.5, 0.001));
      expect(session.transcoding, isTrue);
      expect(session.transcodeDetail, 'Image d\'origine · son AAC');
    });

    test('séance sans lecture : ignorée', () {
      expect(ActiveSession.fromJson({'UserName': 'admin'}), isNull);
    });

    test('place des bibliothèques', () {
      final storage = LibraryStorage.listFromJson({
        'Libraries': [
          {
            'Name': 'Films',
            'Folders': [
              {'FreeSpace': 1000, 'UsedSpace': 3000},
            ],
          },
          {'Name': 'Vide', 'Folders': <Object>[]},
        ],
      });
      expect(storage, hasLength(1));
      expect(storage.first.name, 'Films');
      expect(storage.first.usedFraction, 0.75);
    });

    test('il y a combien de temps', () {
      final now = DateTime(2026, 10, 2, 12);
      expect(timeAgo(now, now: now), 'à l\'instant');
      expect(
        timeAgo(now.subtract(const Duration(minutes: 5)), now: now),
        'il y a 5 min',
      );
      expect(
        timeAgo(now.subtract(const Duration(hours: 3)), now: now),
        'il y a 3 h',
      );
      expect(
        timeAgo(now.subtract(const Duration(days: 2)), now: now),
        'il y a 2 j',
      );
    });
  });
}
