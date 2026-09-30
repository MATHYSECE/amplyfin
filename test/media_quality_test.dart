import 'package:amplyfin/models/media_quality.dart';
import 'package:amplyfin/models/movie_details.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests de la qualité affichée sur la fiche (définition, HDR, son)
void main() {
  Map<String, dynamic> item(List<Map<String, dynamic>> streams) => {
    'Id': 'film1',
    'MediaSources': [
      {'Id': 'source1', 'MediaStreams': streams},
    ],
  };

  test('film 4K HDR10 avec son E-AC3 5.1', () {
    final quality = MediaQuality.fromItemJson(
      item([
        {
          'Type': 'Video',
          'Codec': 'hevc',
          'Width': 3840,
          'Height': 1600,
          'VideoRangeType': 'HDR10',
        },
        {'Type': 'Audio', 'Codec': 'eac3', 'Channels': 6, 'IsDefault': true},
      ]),
    )!;
    expect(quality.labels, ['4K', 'HEVC', 'HDR10', 'E-AC3 5.1']);
  });

  test('format cinéma 1920×800 : bien reconnu comme 1080p', () {
    final quality = MediaQuality(width: 1920, height: 800);
    expect(quality.resolutionLabel, '1080p');
  });

  test('Dolby Vision, TrueHD Atmos 7.1', () {
    final quality = MediaQuality(
      videoRange: 'DOVIWithHDR10',
      audioCodec: 'truehd',
      audioProfile: 'Dolby TrueHD + Dolby Atmos',
      audioChannels: 8,
    );
    expect(quality.hdrLabel, 'Dolby Vision');
    expect(quality.audioLabel, 'TrueHD Atmos 7.1');
  });

  test('vidéo normale (SDR) : pas d\'étiquette HDR', () {
    expect(const MediaQuality(videoRange: 'SDR').hdrLabel, isNull);
  });

  test('prend la piste audio par défaut', () {
    final quality = MediaQuality.fromItemJson(
      item([
        {'Type': 'Video', 'Codec': 'h264', 'Width': 1280, 'Height': 720},
        {'Type': 'Audio', 'Codec': 'aac', 'Channels': 2},
        {'Type': 'Audio', 'Codec': 'dts', 'Channels': 6, 'IsDefault': true},
      ]),
    )!;
    expect(quality.labels, ['720p', 'H.264', 'DTS 5.1']);
  });

  test('aucune piste : pas de qualité', () {
    expect(MediaQuality.fromItemJson({'Id': 'film1'}), isNull);
  });

  test('la fiche du film lit aussi la qualité', () {
    final details = MovieDetails.fromJson(
      item([
        {'Type': 'Video', 'Codec': 'av1', 'Width': 1920, 'Height': 1080},
      ]),
    );
    expect(details.quality?.labels, ['1080p', 'AV1']);
  });
}
