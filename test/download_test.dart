import 'package:amplyfin/models/download_info.dart';
import 'package:amplyfin/models/file_size.dart';
import 'package:amplyfin/models/media_track.dart';
import 'package:amplyfin/services/download_manager.dart';
import 'package:amplyfin/widgets/download_controls.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests des téléchargements
void main() {
  // Fiche d'un épisode telle que renvoyée par GET /Items/{id}
  final episodeJson = {
    'Id': 'ep1',
    'Name': 'Las Vegas',
    'Type': 'Episode',
    'SeriesId': 'malcolm',
    'SeriesName': 'Malcolm',
    'SeriesPrimaryImageTag': 'tag-serie',
    'ParentIndexNumber': 5,
    'IndexNumber': 1,
    'RunTimeTicks': 23 * 60 * 10000000,
    'MediaSources': [
      {
        'Id': 'source1',
        'Container': 'mkv',
        'Size': 1234567890,
        'DefaultAudioStreamIndex': 1,
        'MediaStreams': [
          {'Type': 'Video', 'Index': 0, 'Codec': 'hevc'},
          {'Type': 'Audio', 'Index': 1, 'Language': 'fre', 'Codec': 'eac3'},
          {'Type': 'Subtitle', 'Index': 2, 'Language': 'fre', 'Codec': 'srt'},
          {
            'Type': 'Subtitle',
            'Index': 3,
            'Language': 'eng',
            'Codec': 'srt',
            'IsExternal': true,
          },
        ],
      },
    ],
  };

  group('Taille lisible', () {
    test('à la française', () {
      expect(formatFileSize(12400000000), '12,4 Go');
      expect(formatFileSize(850000000), '850 Mo');
      expect(formatFileSize(1234567890), '1,2 Go');
      expect(formatFileSize(512), '512 o');
    });

    test('inconnue', () {
      expect(formatFileSize(null), isNull);
      expect(formatFileSize(0), isNull);
    });
  });

  group('Infos gardées avec un téléchargement', () {
    test('épisode lu depuis la fiche du serveur', () {
      final info = DownloadInfo.fromItemJson(episodeJson);
      expect(info.itemId, 'ep1');
      expect(info.isEpisode, isTrue);
      expect(info.mediaSourceId, 'source1');
      expect(info.size, 1234567890);
      expect(info.fileName, 'ep1.mkv');
      expect(info.displayName, 'Malcolm · S5E1');
      expect(info.playerTitle, 'Malcolm');
      expect(info.playerSubtitle, 'S5 · É1 · Las Vegas');
      // Affiche : celle de la série
      expect(info.posterItem.id, 'malcolm');
      expect(info.posterItem.posterTag, 'tag-serie');
      expect(info.externalSubtitles.map((t) => t.index), [3]);
    });

    test('film : son affiche, format inconnu → extension neutre', () {
      final info = DownloadInfo.fromItemJson({
        'Id': 'film',
        'Name': '1917',
        'Type': 'Movie',
        'ProductionYear': 2019,
        'ImageTags': {'Primary': 'tag-film'},
        'MediaSources': [
          {'Id': 'film', 'Container': 'mov,mp4,m4a'},
        ],
      });
      expect(info.displayName, '1917');
      expect(info.playerSubtitle, isNull);
      expect(info.posterItem.id, 'film');
      expect(info.fileName, 'film.mov');
      expect(
        DownloadInfo.fromItemJson({'Id': 'x', 'Name': 'x'}).fileName,
        'x.video',
      );
    });

    test('enregistrées puis relues à l\'identique', () {
      final info = DownloadInfo.fromItemJson(episodeJson);
      final copy = DownloadInfo.fromJson(info.toJson());
      expect(copy.toJson(), info.toJson());
      expect(copy.runtime, const Duration(minutes: 23));
      expect(copy.tracks.length, info.tracks.length);
    });
  });

  group('Lecture du fichier téléchargé', () {
    test('fichier du téléphone, sous-titres séparés en local', () {
      final info = DownloadInfo.fromItemJson(episodeJson);
      final playback = info.localPlaybackInfo(
        '/données/ep1.mkv',
        subtitleFiles: {3: '/données/ep1.sub3.srt'},
      );
      expect(playback.isLocal, isTrue);
      expect(playback.directPlay, isTrue);
      expect(playback.localPath, '/données/ep1.mkv');
      expect(playback.defaultAudioIndex, 1);
      final external = playback.track(3)!;
      expect(external.deliveryMethod, 'External');
      expect(external.deliveryUrl, startsWith('file:'));
      // Les pistes du fichier gardent leur place pour le lecteur
      expect(playerTrackId(playback.tracks, playback.track(2)!), 1);
    });

    test('sous-titres séparés absents : piste retirée', () {
      final playback = DownloadInfo.fromItemJson(episodeJson)
          .localPlaybackInfo('/données/ep1.mkv');
      expect(playback.track(3), isNull);
    });
  });

  group('État affiché sous un épisode', () {
    test('selon l\'avancée', () {
      expect(downloadStatusLabel(const DownloadState()), isNull);
      expect(
        downloadStatusLabel(
          const DownloadState(phase: DownloadPhase.running, progress: 0.604),
        ),
        'Téléchargement · 60 %',
      );
      expect(
        downloadStatusLabel(
          const DownloadState(
            phase: DownloadPhase.complete,
            progress: 1,
            expectedSize: 1234567890,
          ),
        ),
        'Téléchargé · 1,2 Go',
      );
      expect(
        downloadStatusLabel(
          const DownloadState(phase: DownloadPhase.failed, error: 'Refusé.'),
        ),
        'Refusé.',
      );
    });

    test('octets reçus d\'après la progression', () {
      const state = DownloadState(
        phase: DownloadPhase.running,
        progress: 0.5,
        expectedSize: 1000,
      );
      expect(state.receivedBytes, 500);
      expect(state.isActive, isTrue);
    });
  });
}
