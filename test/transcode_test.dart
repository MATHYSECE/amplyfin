import 'package:amplyfin/models/playback_info.dart';
import 'package:amplyfin/models/transcode_reasons.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests de la fenêtre « lecture directe impossible » : raisons du serveur
void main() {
  PlaybackInfo converted(String url) => PlaybackInfo.fromJson({
    'PlaySessionId': 's',
    'MediaSources': [
      {
        'Id': 'src',
        'SupportsDirectPlay': false,
        'TranscodingUrl': url,
        'MediaStreams': [
          {'Type': 'Video', 'Index': 0},
          {'Type': 'Audio', 'Index': 1},
        ],
      },
    ],
  }, itemId: 'film');

  group('Raisons lues dans l\'adresse du flux converti', () {
    test('plusieurs raisons', () {
      final info = converted(
        '/videos/film/master.m3u8?MediaSourceId=src'
        '&TranscodeReasons=VideoBitDepthNotSupported,AudioCodecNotSupported',
      );
      expect(info.transcodeReasons, [
        'VideoBitDepthNotSupported',
        'AudioCodecNotSupported',
      ]);
      expect(info.hasVideo, isTrue);
    });

    test('nom du paramètre sans tenir compte des majuscules', () {
      final info = converted(
        '/videos/film/master.m3u8?transcodeReasons=ContainerNotSupported',
      );
      expect(info.transcodeReasons, ['ContainerNotSupported']);
    });

    test('pas de raison donnée : liste vide', () {
      expect(converted('/videos/film/master.m3u8?x=1').transcodeReasons, []);
    });

    test('lecture directe : aucune raison', () {
      final info = PlaybackInfo.fromJson({
        'MediaSources': [
          {'Id': 'src', 'SupportsDirectPlay': true},
        ],
      }, itemId: 'film');
      expect(info.transcodeReasons, isEmpty);
      expect(info.hasVideo, isFalse); // aucune piste listée
    });
  });

  group('Phrases affichées', () {
    test('traduction et doublons retirés', () {
      expect(
        describeTranscodeReasons([
          'VideoCodecNotSupported',
          'VideoProfileNotSupported', // même phrase que la précédente
          'VideoBitDepthNotSupported',
        ]),
        [
          'Ton appareil ne sait pas décoder la vidéo.',
          'Ton appareil ne sait pas lire la vidéo en 10\u00A0bits.',
        ],
      );
    });

    test('code inconnu : phrase générale', () {
      expect(describeTranscodeReasons(['NouveauCode']), [
        'Ce fichier ne peut pas être lu tel quel.',
      ]);
    });
  });
}
