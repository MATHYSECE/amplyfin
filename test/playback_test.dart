import 'package:amplyfin/api/device_profile.dart';
import 'package:amplyfin/api/jellyfin_api.dart';
import 'package:amplyfin/models/movie_details.dart';
import 'package:amplyfin/models/playback_info.dart';
import 'package:amplyfin/models/playback_quality.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests de la lecture : profil de l'appareil, réponse du serveur, adresses
void main() {
  group('buildDeviceProfile', () {
    final profile = buildDeviceProfile(maxBitrate: originalMaxBitrate);

    test('annonce la lecture directe de tous les codecs', () {
      final directPlay = profile['DirectPlayProfiles'] as List;
      expect(directPlay, hasLength(1));
      final video = directPlay.first as Map;
      expect(video['Type'], 'Video');
      expect(video['Container'], contains('mkv'));
      expect(video['Container'], contains('mp4'));
      // Aucun codec listé = tous acceptés
      expect(video.containsKey('VideoCodec'), isFalse);
      expect(video.containsKey('AudioCodec'), isFalse);
    });

    test('propose un flux HLS de secours', () {
      final transcoding = (profile['TranscodingProfiles'] as List).first;
      expect(transcoding['Protocol'], 'hls');
      expect(transcoding['VideoCodec'], 'h264,hevc');
    });

    test('affiche les sous-titres PGS lui-même (pas d\'incrustation)', () {
      final subtitles = profile['SubtitleProfiles'] as List;
      expect(
        subtitles,
        contains(equals({'Format': 'pgssub', 'Method': 'Embed'})),
      );
    });

    test('reprend le débit maximum demandé', () {
      final low = buildDeviceProfile(maxBitrate: 3000000);
      expect(low['MaxStreamingBitrate'], 3000000);
    });

    test('qualité originale : aucune limite de largeur', () {
      expect(profile.containsKey('CodecProfiles'), isFalse);
    });

    test('qualité réduite : largeur maximum imposée', () {
      final low = buildDeviceProfile(maxBitrate: 8000000, maxWidth: 1280);
      final condition = (low['CodecProfiles'] as List).first['Conditions'][0];
      expect(condition, {
        'Condition': 'LessThanEqual',
        'Property': 'Width',
        'Value': '1280',
        'IsRequired': true,
      });
    });
  });

  group('PlaybackInfo.fromJson', () {
    test('lecture directe possible', () {
      final info = PlaybackInfo.fromJson({
        'PlaySessionId': 'seance1',
        'MediaSources': [
          {'Id': 'source1', 'SupportsDirectPlay': true},
        ],
      }, itemId: 'film1');
      expect(info.directPlay, isTrue);
      expect(info.playMethod, 'DirectPlay');
      expect(info.mediaSourceId, 'source1');
      expect(info.playSessionId, 'seance1');
    });

    test('flux converti', () {
      final info = PlaybackInfo.fromJson({
        'PlaySessionId': 'seance1',
        'MediaSources': [
          {
            'Id': 'source1',
            'SupportsDirectPlay': false,
            'TranscodingUrl': '/videos/film1/master.m3u8?x=1',
          },
        ],
      }, itemId: 'film1');
      expect(info.directPlay, isFalse);
      expect(info.playMethod, 'Transcode');
    });

    test('refus du serveur : message lisible', () {
      expect(
        () => PlaybackInfo.fromJson({
          'ErrorCode': 'NotAllowed',
          'MediaSources': [],
        }, itemId: 'film1'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('pas le droit'),
          ),
        ),
      );
    });

    test('aucune source : erreur', () {
      expect(
        () => PlaybackInfo.fromJson({'MediaSources': []}, itemId: 'film1'),
        throwsFormatException,
      );
    });
  });

  group('streamUrl', () {
    final api = JellyfinApi(
      serverUrl: 'http://serveur:8096/jellyfin',
      deviceId: 'appareil1',
    );

    test('lecture directe : fichier original', () {
      const info = PlaybackInfo(
        itemId: 'film1',
        mediaSourceId: 'source1',
        playSessionId: 'seance1',
        directPlay: true,
      );
      expect(
        api.streamUrl(info),
        'http://serveur:8096/jellyfin/Videos/film1/stream?static=true'
        '&mediaSourceId=source1&playSessionId=seance1&deviceId=appareil1',
      );
    });

    test('flux converti : adresse partielle complétée', () {
      const info = PlaybackInfo(
        itemId: 'film1',
        mediaSourceId: 'source1',
        playSessionId: 'seance1',
        directPlay: false,
        transcodingUrl: '/videos/film1/master.m3u8?x=1',
      );
      expect(
        api.streamUrl(info),
        'http://serveur:8096/jellyfin/videos/film1/master.m3u8?x=1',
      );
    });
  });

  test('qualités : la première est l\'originale, sans limite', () {
    expect(PlaybackQuality.all.first.isOriginal, isTrue);
    expect(PlaybackQuality.all.first.maxBitrate, isNull);
    expect(PlaybackQuality.all.first.maxWidth, isNull);
    for (final quality in PlaybackQuality.all.skip(1)) {
      expect(quality.maxBitrate, isNotNull);
      expect(quality.maxWidth, isNotNull);
    }
  });

  test('position en ticks', () {
    expect(durationToTicks(const Duration(seconds: 1)), 10000000);
    expect(
      ticksToDuration(durationToTicks(const Duration(minutes: 42))),
      const Duration(minutes: 42),
    );
  });
}
