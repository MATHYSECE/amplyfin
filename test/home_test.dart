import 'package:amplyfin/models/home_items.dart';
import 'package:amplyfin/models/resume_entry.dart';
import 'package:amplyfin/models/watch_progress.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests de la page d'accueil
void main() {
  final now = DateTime(2026, 10, 1, 20);

  group('Petites lignes', () {
    test(
      'épisode suivant, ou nouvel épisode (ajouté depuis moins de 14 jours)',
      () {
        expect(
          nextUpLabel(now.subtract(const Duration(days: 3)), now),
          'Nouvel épisode',
        );
        expect(
          nextUpLabel(now.subtract(const Duration(days: 30)), now),
          'Épisode suivant',
        );
        expect(nextUpLabel(null, now), 'Épisode suivant');
      },
    );

    test('date d\'ajout d\'un film', () {
      expect(addedLabel(DateTime(2026, 10, 1, 9), now), 'Ajouté aujourd\'hui');
      expect(addedLabel(DateTime(2026, 9, 30, 23), now), 'Ajouté hier');
      expect(addedLabel(DateTime(2026, 9, 27), now), 'Ajouté il y a 4 jours');
      // Plus d'une semaine, ou inconnue : l'année du film
      expect(addedLabel(DateTime(2026, 8, 1), now, year: 2024), '2024');
      expect(addedLabel(null, now, year: 2019), '2019');
    });
  });

  group('Continuer à regarder, comme Netflix', () {
    Map<String, dynamic> episode(
      String id,
      String series, {
      String? lastPlayed,
      int position = 0,
    }) => {
      'Id': id,
      'Type': 'Episode',
      'Name': 'Épisode',
      'SeriesId': series,
      'SeriesName': series,
      'ParentIndexNumber': 1,
      'IndexNumber': 2,
      'UserData': {
        'PlaybackPositionTicks': position,
        'LastPlayedDate': ?lastPlayed,
      },
    };
    Map<String, dynamic> movie(String id, String lastPlayed) => {
      'Id': id,
      'Type': 'Movie',
      'Name': id,
      'UserData': {
        'PlaybackPositionTicks': 600000000,
        'LastPlayedDate': lastPlayed,
      },
    };

    final resume = [
      ResumeEntry.fromJson(movie('dune', '2026-10-01T18:00:00Z')),
      ResumeEntry.fromJson(
        episode('malcolm-e1', 'malcolm', lastPlayed: '2026-09-28T18:00:00Z'),
      ),
    ];
    final next = [
      // Série regardée hier soir : entre Dune et Malcolm
      ResumeEntry.fromJson(
        episode('dark-e4', 'dark'),
        nextLabel: 'Nouvel épisode',
      ),
      // Malcolm a déjà un épisode commencé : pas d'épisode suivant en plus
      ResumeEntry.fromJson(
        episode('malcolm-e2', 'malcolm'),
        nextLabel: 'Épisode suivant',
      ),
      // Date inconnue : à la fin
      ResumeEntry.fromJson(
        episode('office-e8', 'office'),
        nextLabel: 'Épisode suivant',
      ),
    ];

    test('du plus récent au plus ancien, une seule fois par série', () {
      final merged = mergeContinueWatching(resume, next, {
        'dark': WatchProgress(
          percentage: 40,
          lastPlayed: DateTime.utc(2026, 9, 30, 21),
        ),
        'malcolm': WatchProgress(
          percentage: 10,
          lastPlayed: DateTime.utc(2026, 9, 28, 18),
        ),
      });
      expect(merged.map((e) => e.id), [
        'dune',
        'dark-e4',
        'malcolm-e1',
        'office-e8',
      ]);
      expect(merged[1].isNext, isTrue);
      expect(merged[1].nextLabel, 'Nouvel épisode');
      expect(merged[0].isNext, isFalse);
    });

    test('rien de commencé : seulement les épisodes suivants', () {
      final merged = mergeContinueWatching(const [], next, const {});
      // Pas de dates : l'ordre du serveur est gardé
      expect(merged.map((e) => e.id), ['dark-e4', 'malcolm-e2', 'office-e8']);
    });

    test('série jamais vraiment commencée : pas d\'épisode suivant', () {
      // Aucun épisode vu (épisode 1 juste lancé, ou retiré) : écartée
      final merged = mergeContinueWatching(const [], next, {
        'dark': WatchProgress(
          percentage: 0,
          lastPlayed: DateTime.utc(2026, 9, 30),
        ),
        'office': const WatchProgress(percentage: 25),
        // Série entièrement vue, puis un nouvel épisode : gardée
        'malcolm': const WatchProgress(played: true),
      });
      expect(merged.map((e) => e.id), ['malcolm-e2', 'office-e8']);
    });
  });

  group('Nouveaux épisodes', () {
    test('plusieurs épisodes : la série, avec leur nombre', () {
      final entry = NewEpisodesEntry.fromLatestJson({
        'Id': 'malcolm',
        'Type': 'Series',
        'Name': 'Malcolm',
        'ImageTags': {'Primary': 'tag-serie'},
        'ChildCount': 3,
      });
      expect(entry.series.id, 'malcolm');
      expect(entry.series.isSeries, isTrue);
      expect(entry.series.posterTag, 'tag-serie');
      expect(entry.count, 3);
      expect(entry.label, '3 nouveaux épisodes');
      expect(entry.seasonId, isNull);
    });

    test('un seul épisode : sa série, ouverte sur sa saison', () {
      final entry = NewEpisodesEntry.fromLatestJson({
        'Id': 'ep',
        'Type': 'Episode',
        'Name': 'Las Vegas',
        'SeriesId': 'malcolm',
        'SeriesName': 'Malcolm',
        'SeriesPrimaryImageTag': 'tag-serie',
        'SeasonId': 'saison5',
        'ParentIndexNumber': 5,
        'IndexNumber': 1,
      });
      expect(entry.series.id, 'malcolm');
      expect(entry.series.name, 'Malcolm');
      expect(entry.series.posterTag, 'tag-serie');
      expect(entry.count, 1);
      expect(entry.label, 'S5 · É1');
      expect(entry.seasonId, 'saison5');
    });

    test('une saison regroupée', () {
      final entry = NewEpisodesEntry.fromLatestJson({
        'Id': 'saison2',
        'Type': 'Season',
        'Name': 'Saison 2',
        'SeriesId': 'dark',
        'SeriesName': 'Dark',
        'ChildCount': 2,
      });
      expect(entry.series.id, 'dark');
      expect(entry.label, '2 nouveaux épisodes');
      expect(entry.seasonId, 'saison2');
    });
  });

  group('À la une', () {
    Map<String, dynamic> film(String id, {bool backdrop = true}) => {
      'Id': id,
      'Type': 'Movie',
      'Name': id,
      'ProductionYear': 2024,
      'Genres': ['Science-fiction', 'Aventure', 'Drame'],
      'RunTimeTicks': 166 * 60 * 10000000,
      if (backdrop) 'BackdropImageTags': ['fond-$id'],
    };
    Map<String, dynamic> series(String id, int count) => {
      'Id': id,
      'Type': 'Series',
      'Name': id,
      'ChildCount': count,
      'BackdropImageTags': ['fond-$id'],
    };

    test('films et séries en alternance, avec image de fond', () {
      final hero = pickHeroItems(
        [
          film('dune'),
          film('sans-fond', backdrop: false),
          film('blade'),
          film('parasite'),
        ],
        [
          series('malcolm', 3),
          // Épisode seul : ni résumé ni fond de série, pas à la une
          {'Id': 'ep', 'Type': 'Episode', 'SeriesId': 'dark'},
          series('chernobyl', 1),
        ],
      );
      expect(hero.map((h) => h.item.id), [
        'dune',
        'malcolm',
        'blade',
        'chernobyl',
        'parasite',
      ]);
      expect(hero[0].eyebrow, 'Nouveau film');
      expect(hero[1].eyebrow, '3 nouveaux épisodes');
      expect(hero[3].eyebrow, 'Nouvel épisode');
      // Deux genres au plus
      expect(hero[0].infoLine, '2024 · Science-fiction · Aventure · 2 h 46');
    });

    test('au plus 5, et rien sans nouveautés', () {
      expect(
        pickHeroItems([
          for (var i = 0; i < 9; i++) film('f$i'),
        ], const []).length,
        5,
      );
      expect(pickHeroItems(const [], const []), isEmpty);
    });
  });
}
