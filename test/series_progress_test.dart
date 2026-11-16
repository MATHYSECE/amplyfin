import 'package:amplyfin/models/episode.dart';
import 'package:amplyfin/models/season.dart';
import 'package:amplyfin/models/series_progress.dart';
import 'package:amplyfin/models/watch_progress.dart';
import 'package:flutter_test/flutter_test.dart';

Episode _episode(
  int season,
  int number, {
  bool played = false,
  Duration position = Duration.zero,
  DateTime? lastPlayed,
}) => Episode(
  id: 's${season}e$number',
  name: 'Épisode $number',
  seasonNumber: season,
  number: number,
  progress: WatchProgress(
    played: played,
    position: position,
    lastPlayed: lastPlayed,
  ),
);

void main() {
  const specials = Season(id: 's0', name: 'Spéciaux', number: 0);
  const one = Season(id: 's1', name: 'Saison 1', number: 1);
  const two = Season(id: 's2', name: 'Saison 2', number: 2);

  test('rien de chargé : pas de bouton', () {
    expect(pickEpisodeToWatch(const [], const {}), isNull);
    expect(pickEpisodeToWatch(const [one], const {}), isNull);
  });

  test('série jamais commencée : le premier épisode, pas un spécial', () {
    final pick = pickEpisodeToWatch(
      const [specials, one],
      {
        's0': [_episode(0, 1)],
        's1': [_episode(1, 1), _episode(1, 2)],
      },
    )!;
    expect(pick.episode.id, 's1e1');
    expect(pick.resume, isFalse);
    expect(pick.label, 'Lecture S1 · É1');
  });

  test('seulement des spéciaux : le premier spécial', () {
    final pick = pickEpisodeToWatch(
      const [specials],
      {
        's0': [_episode(0, 1)],
      },
    )!;
    expect(pick.episode.id, 's0e1');
  });

  test('après le dernier épisode vu, même dans la saison suivante', () {
    final pick = pickEpisodeToWatch(
      const [one, two],
      {
        's1': [_episode(1, 1, played: true), _episode(1, 2, played: true)],
        's2': [_episode(2, 1), _episode(2, 2)],
      },
    )!;
    expect(pick.episode.id, 's2e1');
    expect(pick.label, 'Lecture S2 · É1');
  });

  test('épisode commencé : le plus récent passe avant le suivant', () {
    final pick = pickEpisodeToWatch(
      const [one],
      {
        's1': [
          _episode(1, 1, played: true),
          _episode(
            1,
            2,
            position: const Duration(minutes: 5),
            lastPlayed: DateTime(2026, 11, 1),
          ),
          _episode(
            1,
            3,
            position: const Duration(minutes: 9),
            lastPlayed: DateTime(2026, 11, 10),
          ),
        ],
      },
    )!;
    expect(pick.episode.id, 's1e3');
    expect(pick.resume, isTrue);
    expect(pick.label, 'Reprendre S1 · É3');
  });

  test('tout vu : on repart du premier', () {
    final pick = pickEpisodeToWatch(
      const [one],
      {
        's1': [_episode(1, 1, played: true), _episode(1, 2, played: true)],
      },
    )!;
    expect(pick.episode.id, 's1e1');
    expect(pick.resume, isFalse);
  });
}
