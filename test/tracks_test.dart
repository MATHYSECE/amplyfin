import 'package:amplyfin/models/item_details.dart';
import 'package:amplyfin/models/languages.dart';
import 'package:amplyfin/models/media_track.dart';
import 'package:amplyfin/models/playback_info.dart';
import 'package:amplyfin/models/track_choice.dart';
import 'package:amplyfin/services/track_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Tests des pistes audio et sous-titres
void main() {
  // Pistes d'un épisode typique : vidéo, 2 audios, 3 sous-titres dont un
  // externe (fichier .srt à part)
  final streams = [
    {'Type': 'Video', 'Index': 0, 'Codec': 'hevc'},
    {
      'Type': 'Audio',
      'Index': 1,
      'Language': 'fre',
      'Codec': 'eac3',
      'Channels': 6,
      'IsDefault': true,
    },
    {'Type': 'Audio', 'Index': 2, 'Language': 'eng', 'Codec': 'aac'},
    {
      'Type': 'Subtitle',
      'Index': 3,
      'Language': 'fra',
      'Codec': 'subrip',
      'IsForced': true,
    },
    {'Type': 'Subtitle', 'Index': 4, 'Language': 'fre', 'Codec': 'subrip'},
    {
      'Type': 'Subtitle',
      'Index': 5,
      'Language': 'eng',
      'Codec': 'subrip',
      'IsExternal': true,
      'DeliveryMethod': 'External',
      'DeliveryUrl': '/Videos/ep/src/Subtitles/5/0/Stream.srt',
    },
  ];
  final tracks = tracksFromStreams(streams);

  group('Langues', () {
    test('codes unifiés et noms en français', () {
      expect(normalizeLanguage('fra'), 'fre');
      expect(normalizeLanguage('und'), isNull);
      expect(languageName('fre'), 'Français');
      expect(languageName('deu'), 'Allemand');
      expect(languageName('xyz'), 'XYZ');
      expect(languageName(null), 'Langue inconnue');
    });
  });

  group('MediaTrack', () {
    test('garde seulement l\'audio et les sous-titres', () {
      expect(tracks, hasLength(5));
      expect(tracks.first.type, TrackType.audio);
    });

    test('noms affichés dans les menus', () {
      expect(tracks[0].label, 'Français · E-AC3 5.1');
      expect(tracks[2].label, 'Français (forcés) · SRT');
      expect(tracks[4].label, 'Anglais · SRT');
    });

    test('numéro pour le lecteur : compté par type, sans les externes', () {
      expect(playerTrackId(tracks, tracks[0]), 1); // 1re piste audio
      expect(playerTrackId(tracks, tracks[1]), 2); // 2e piste audio
      expect(playerTrackId(tracks, tracks[2]), 1); // 1ers sous-titres
      expect(playerTrackId(tracks, tracks[3]), 2);
      expect(playerTrackId(tracks, tracks[4]), isNull); // externe
    });
  });

  group('Choix par langue (séries)', () {
    test('par défaut : on laisse le serveur choisir', () {
      final selection = const LanguagePreference().resolve(tracks);
      expect(selection.audioIndex, isNull);
      expect(selection.subtitleIndex, isNull);
    });

    test('anglais + sous-titres français complets (pas les forcés)', () {
      final selection = const LanguagePreference(
        audioLanguage: 'eng',
        subtitleLanguage: 'fre',
      ).resolve(tracks);
      expect(selection.audioIndex, 2);
      expect(selection.subtitleIndex, 4);
    });

    test('sous-titres désactivés', () {
      final selection = const LanguagePreference(
        subtitleLanguage: LanguagePreference.noSubtitles,
      ).resolve(tracks);
      expect(selection.subtitleIndex, TrackSelection.noSubtitles);
    });

    test('langue absente de l\'épisode : choix du serveur', () {
      final selection = const LanguagePreference(audioLanguage: 'jpn')
          .resolve(tracks);
      expect(selection.audioIndex, isNull);
    });

    test('seulement des sous-titres forcés : on les prend', () {
      final forcedOnly = tracksFromStreams([
        {'Type': 'Subtitle', 'Index': 7, 'Language': 'fre', 'IsForced': true},
      ]);
      final selection = const LanguagePreference(subtitleLanguage: 'fre')
          .resolve(forcedOnly);
      expect(selection.subtitleIndex, 7);
    });

    test('liste des langues sans doublons', () {
      expect(languagesOf(tracks, TrackType.subtitle), ['fre', 'eng']);
      expect(languagesOf(tracks, TrackType.audio), ['fre', 'eng']);
    });

    test('textes affichés', () {
      const preference = LanguagePreference(
        audioLanguage: 'eng',
        subtitleLanguage: LanguagePreference.noSubtitles,
      );
      expect(preference.audioLabel, 'Anglais');
      expect(preference.subtitleLabel, 'Aucun');
      expect(const LanguagePreference().audioLabel, 'Par défaut');
    });
  });

  group('Réponses du serveur', () {
    test('PlaybackInfo : pistes et choix par défaut', () {
      final info = PlaybackInfo.fromJson({
        'PlaySessionId': 's',
        'MediaSources': [
          {
            'Id': 'src',
            'SupportsDirectPlay': true,
            'MediaStreams': streams,
            'DefaultAudioStreamIndex': 1,
            'DefaultSubtitleStreamIndex': -1,
          },
        ],
      }, itemId: 'ep');
      expect(info.audioTracks, hasLength(2));
      expect(info.subtitleTracks, hasLength(3));
      expect(info.defaultAudioIndex, 1);
      expect(info.defaultSubtitleIndex, -1);
      expect(info.track(5)?.deliveryMethod, 'External');
      expect(info.track(99), isNull);
    });

    test('fiche d\'un film : pistes du premier fichier', () {
      final details = ItemDetails.fromJson({
        'Id': 'film',
        'MediaSources': [
          {'Id': 'src', 'MediaStreams': streams, 'DefaultAudioStreamIndex': 2},
        ],
      });
      expect(details.audioTracks.map((t) => t.index), [1, 2]);
      expect(details.defaultAudioIndex, 2);
    });
  });

  test('le choix d\'une série est retenu sur le téléphone', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = TrackPreferences();
    expect((await preferences.load('serie1')).audioLanguage, isNull);

    await preferences.save(
      'serie1',
      const LanguagePreference(audioLanguage: 'eng', subtitleLanguage: 'fre'),
    );
    final loaded = await preferences.load('serie1');
    expect(loaded.audioLanguage, 'eng');
    expect(loaded.subtitleLanguage, 'fre');
    // Une autre série n'est pas concernée
    expect((await preferences.load('serie2')).audioLanguage, isNull);
  });
}
