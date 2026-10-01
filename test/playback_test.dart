import 'package:amplyfin/api/device_profile.dart';
import 'package:amplyfin/api/jellyfin_api.dart';
import 'package:amplyfin/models/device_decoders.dart';
import 'package:amplyfin/models/durations.dart';
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

    List<Map<String, dynamic>> conditionsOf(
      Map<String, dynamic> profile, {
      String? codec,
    }) {
      final codecProfile = (profile['CodecProfiles'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((p) => p['Codec'] == codec);
      return (codecProfile['Conditions'] as List).cast<Map<String, dynamic>>();
    }

    test('qualité originale : aucune limite de largeur', () {
      expect(
        conditionsOf(profile).map((c) => c['Property']),
        isNot(contains('Width')),
      );
    });

    test('Dolby Vision profil 5 converti, profil 8 lu comme du HDR10', () {
      final range = conditionsOf(profile)
          .firstWhere((c) => c['Property'] == 'VideoRangeType');
      final types = (range['Value'] as String).split('|');
      expect(range['Condition'], 'EqualsAny');
      expect(types, containsAll(['SDR', 'HDR10', 'HLG', 'DOVIWithHDR10']));
      expect(types, isNot(contains('DOVI')));
    });

    test('appareil sans 10 bits : profondeur de couleur limitée à 8', () {
      final emulator = buildDeviceProfile(
        maxBitrate: originalMaxBitrate,
        decoders: const DeviceDecoders(allow10Bit: false),
      );
      final bitDepth = conditionsOf(emulator)
          .firstWhere((c) => c['Property'] == 'VideoBitDepth');
      expect(bitDepth['Value'], '8');
    });

    test('qualité réduite : largeur maximum imposée', () {
      final low = buildDeviceProfile(maxBitrate: 8000000, maxWidth: 1280);
      expect(conditionsOf(low).first, {
        'Condition': 'LessThanEqual',
        'Property': 'Width',
        'Value': '1280',
        'IsRequired': true,
      });
    });

    group('selon la puce vidéo', () {
      // Comme la tablette Huawei M5 : HEVC 4K mais pas en 10 bits, pas d'AV1
      final tablet = buildDeviceProfile(
        maxBitrate: originalMaxBitrate,
        decoders: DeviceDecoders.fromMap({
          'codecs': {
            'h264': {'hardware': true, 'maxWidth': 3840, 'maxHeight': 2160},
            'hevc': {
              'hardware': true,
              'maxWidth': 3840,
              'maxHeight': 2160,
              'tenBit': false,
            },
            'vp9': {'hardware': true, 'maxWidth': 3840, 'tenBit': true},
          },
        }),
      );

      test('liste des codecs lus directement', () {
        final video = (tablet['DirectPlayProfiles'] as List).first as Map;
        final codecs = (video['VideoCodec'] as String).split(',');
        expect(codecs, containsAll(['h264', 'hevc', 'av1', 'mpeg2video']));
      });

      test("HEVC jusqu'en 4K, mais en 8 bits seulement", () {
        final hevc = conditionsOf(tablet, codec: 'hevc');
        expect(hevc.first['Value'], '3840');
        expect(
          hevc.firstWhere((c) => c['Property'] == 'VideoBitDepth')['Value'],
          '8',
        );
      });

      test('10 bits accepté quand la puce le lit', () {
        final vp9 = conditionsOf(tablet, codec: 'vp9');
        expect(vp9.map((c) => c['Property']), ['Width']);
      });

      test("sans la puce : processeur jusqu'en 1080p, 8 bits", () {
        final av1 = conditionsOf(tablet, codec: 'av1');
        expect(av1.first['Value'], '1920');
        expect(av1.map((c) => c['Property']), contains('VideoBitDepth'));
      });

      test('conversion en H.264 si la puce ne lit pas le HEVC', () {
        final old = buildDeviceProfile(
          maxBitrate: originalMaxBitrate,
          decoders: DeviceDecoders.fromMap({
            'codecs': {
              'h264': {'hardware': true, 'maxWidth': 1920},
            },
          }),
        );
        final transcoding = (old['TranscodingProfiles'] as List).first;
        expect(transcoding['VideoCodec'], 'h264');
        expect(
          (tablet['TranscodingProfiles'] as List).first['VideoCodec'],
          'h264,hevc',
        );
      });
    });

    test('définition lisible de la puce', () {
      expect(const CodecSupport(maxWidth: 3840).resolutionLabel, '4K');
      expect(const CodecSupport(maxWidth: 1920).resolutionLabel, '1080p');
      expect(const CodecSupport().resolutionLabel, isNull);
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

  test('position façon chronomètre', () {
    expect(formatPosition(const Duration(minutes: 12, seconds: 58)), '12:58');
    expect(formatPosition(const Duration(seconds: 5)), '00:05');
    expect(
      formatPosition(const Duration(hours: 1, minutes: 5, seconds: 9)),
      '1:05:09',
    );
    expect(formatPosition(const Duration(seconds: -3)), '00:00');
  });

  test('position en ticks', () {
    expect(durationToTicks(const Duration(seconds: 1)), 10000000);
    expect(
      ticksToDuration(durationToTicks(const Duration(minutes: 42))),
      const Duration(minutes: 42),
    );
  });
}
