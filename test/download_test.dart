import 'package:amplyfin/models/download_info.dart';
import 'package:amplyfin/models/episode.dart';
import 'package:amplyfin/models/file_size.dart';
import 'package:amplyfin/models/media_track.dart';
import 'package:amplyfin/services/download_groups.dart';
import 'package:amplyfin/services/download_manager.dart';
import 'package:amplyfin/widgets/download_controls.dart';
import 'package:amplyfin/widgets/download_rows.dart';
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
    'SeasonId': 'saison5',
    'Overview': 'La famille part à Las Vegas.',
    'ImageTags': {'Primary': 'tag-vignette'},
    'ParentBackdropItemId': 'malcolm',
    'ParentBackdropImageTags': ['tag-fond-serie'],
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
      // Résumé, saison, vignette, et fond de la série
      expect(info.overview, 'La famille part à Las Vegas.');
      expect(info.seasonId, 'saison5');
      expect(info.imageTag, 'tag-vignette');
      expect(info.backdropItemId, 'malcolm');
      expect(info.backdropTag, 'tag-fond-serie');
      expect(info.episodeCode, 'S5 · É1');
      expect(info.episodeTitle, '1. Las Vegas');
    });

    test('film : son propre fond, pas de vignette', () {
      final info = DownloadInfo.fromItemJson({
        'Id': 'film',
        'Name': '1917',
        'Type': 'Movie',
        'ImageTags': {'Primary': 'tag-film'},
        'BackdropImageTags': ['tag-fond'],
      });
      expect(info.backdropItemId, 'film');
      expect(info.backdropTag, 'tag-fond');
      expect(info.imageTag, isNull);
      expect(info.episodeCode, isNull);
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

  group('Rangement de l\'écran Téléchargements', () {
    DownloadInfo movie(String id) =>
        DownloadInfo(itemId: id, name: id, mediaSourceId: id);
    DownloadInfo episode(String id, int season, int number) => DownloadInfo(
      itemId: id,
      name: 'Épisode $number',
      mediaSourceId: id,
      isEpisode: true,
      seriesId: 'malcolm',
      seriesName: 'Malcolm',
      seasonNumber: season,
      episodeNumber: number,
      size: 600000000,
    );
    DownloadState state(
      DownloadPhase phase,
      DownloadInfo info,
      int minute, {
      double progress = 1,
    }) => DownloadState(
      phase: phase,
      progress: progress,
      info: info,
      createdAt: DateTime(2026, 10, 1, 12, minute),
    );

    final states = {
      '1917': state(DownloadPhase.complete, movie('1917'), 1),
      'dune': state(DownloadPhase.running, movie('dune'), 5, progress: 0.2),
      'inter': state(DownloadPhase.paused, movie('inter'), 3, progress: 0.4),
      'couteaux': state(DownloadPhase.complete, movie('couteaux'), 4),
      'e52': state(DownloadPhase.complete, episode('e52', 5, 2), 6),
      'e51': state(DownloadPhase.complete, episode('e51', 5, 1), 7),
      'e41': state(DownloadPhase.complete, episode('e41', 4, 1), 8),
      'e53': state(DownloadPhase.waiting, episode('e53', 5, 3), 9),
      // Fiche pas encore arrivée : pas encore affiché
      'sans-fiche': const DownloadState(phase: DownloadPhase.waiting),
    };

    test('en cours, films et séries', () {
      final groups = DownloadGroups.of(states);
      // En cours : du plus ancien au plus récent
      expect(groups.pending.map((e) => e.id), ['inter', 'dune', 'e53']);
      // Films terminés : du plus récent au plus ancien
      expect(groups.movies.map((e) => e.id), ['couteaux', '1917']);
      expect(groups.series.single.name, 'Malcolm');
      expect(groups.isEmpty, isFalse);
    });

    test('épisodes rangés par saison puis par numéro', () {
      final series = DownloadGroups.of(states).series.single;
      expect(series.episodes.map((e) => e.id), ['e41', 'e51', 'e52', 'e53']);
      expect(series.bySeason.keys, [4, 5]);
      expect(series.complete.length, 3);
      expect(series.pendingCount, 1);
      expect(series.completeBytes, 1800000000);
      // Espaces insécables : une info n'est jamais coupée en fin de ligne
      expect(
        seriesSummary(series).replaceAll('\u00A0', ' '),
        '3 épisodes · 1,8 Go · 1 en cours',
      );
    });

    test('saison ouverte sur la fiche : là où on en est', () {
      final series = DownloadGroups.of(states).series.single;
      // Rien de vu : le premier épisode téléchargé (saison 4)
      expect(series.episodeToOpen(isWatched: (_) => false).itemId, 'e41');
      // Saison 4 vue : la saison 5
      expect(
        series.episodeToOpen(isWatched: (id) => id == 'e41').itemId,
        'e51',
      );
      // Tout vu : le dernier téléchargé
      expect(series.episodeToOpen(isWatched: (_) => true).itemId, 'e41');
    });

    test('suppression en attente : cachée', () {
      final groups = DownloadGroups.of(
        states,
        hidden: {'1917', 'e41', 'e51', 'e52'},
      );
      expect(groups.movies.map((e) => e.id), ['couteaux']);
      // Plus d'épisode terminé : la série quitte la liste des séries…
      expect(groups.series, isEmpty);
      // … mais reste connue (épisode en cours)
      expect(groups.allSeries['malcolm']?.episodes.length, 1);
    });

    test('rien du tout', () {
      expect(DownloadGroups.of(const {}).isEmpty, isTrue);
    });

    test('textes d\'avancée', () {
      expect(
        pendingLabel(
          const DownloadState(
            phase: DownloadPhase.running,
            progress: 0.17,
            expectedSize: 18700000000,
          ),
        ),
        '3,2 Go / 18,7 Go · 17 %',
      );
      expect(
        pendingLabel(
          const DownloadState(phase: DownloadPhase.paused, progress: 0.42),
        ),
        'En pause · 42 %',
      );
      expect(
        pendingLabel(const DownloadState(phase: DownloadPhase.waiting)),
        'En attente…',
      );
    });
  });

  group('Télécharger la saison', () {
    Episode ep(String id, {int? size}) =>
        Episode(id: id, name: id, fileSize: size);
    final episodes = [
      ep('a', size: 600),
      ep('b', size: 600),
      ep('c', size: 600),
      ep('d'),
    ];

    test('rien de téléchargé', () {
      final s = SeasonDownloadSummary.of(
        episodes,
        (_) => const DownloadState(),
      );
      expect(s.missingIds, ['a', 'b', 'c', 'd']);
      // Taille inconnue pour « d » : on additionne ce qu'on connaît
      expect(s.missingBytes, 1800);
      expect(s.isDownloading, isFalse);
      expect(s.isComplete, isFalse);
    });

    test('en partie téléchargée, en cours, et en échec', () {
      final s = SeasonDownloadSummary.of(
        episodes,
        (id) => switch (id) {
          'a' => const DownloadState(
            phase: DownloadPhase.complete,
            progress: 1,
            expectedSize: 600,
          ),
          'b' => const DownloadState(
            phase: DownloadPhase.running,
            progress: 0.5,
          ),
          'c' => const DownloadState(phase: DownloadPhase.failed),
          _ => const DownloadState(),
        },
      );
      expect(s.completeIds, ['a']);
      expect(s.pendingIds, ['b']);
      // L'échec est à retélécharger
      expect(s.missingIds, ['c', 'd']);
      expect(s.tracked, 2);
      expect(s.progress, 0.75);
      expect(s.isDownloading, isTrue);
      expect(s.completeBytes, 600);
    });

    test('toute la saison téléchargée', () {
      final s = SeasonDownloadSummary.of(
        episodes,
        (_) => const DownloadState(phase: DownloadPhase.complete, progress: 1),
      );
      expect(s.isComplete, isTrue);
      expect(s.missingIds, isEmpty);
    });

    test('taille des épisodes lue dans la réponse du serveur', () {
      final episode = Episode.fromJson({
        'Id': 'e1',
        'Name': 'Pilote',
        'MediaSources': [
          {'Id': 's1', 'Size': 620000000},
        ],
      });
      expect(episode.fileSize, 620000000);
      expect(Episode.fromJson({'Id': 'e2'}).fileSize, isNull);
    });
  });
}
