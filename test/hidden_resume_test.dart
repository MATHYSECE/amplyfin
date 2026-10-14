import 'package:amplyfin/models/media_item.dart';
import 'package:amplyfin/models/resume_entry.dart';
import 'package:amplyfin/models/watch_progress.dart';
import 'package:amplyfin/services/hidden_resume.dart';
import 'package:flutter_test/flutter_test.dart';

ResumeEntry _entry(String id, Duration position) => ResumeEntry(
  id: id,
  poster: MediaItem(id: id, name: id),
  title: id,
  subtitle: '',
  playerTitle: id,
  progress: WatchProgress(position: position),
);

void main() {
  test('Retiré en gardant la progression : reste caché tant qu\'on ne le '
      'relance pas', () {
    final result = applyHiddenResume(
      [
        _entry('a', const Duration(minutes: 12)),
        _entry('b', const Duration(minutes: 5)),
      ],
      {'a': const Duration(minutes: 12).inMilliseconds},
    );
    expect(result.visible.map((e) => e.id), ['b']);
    expect(result.stale, isEmpty);
  });

  test('Relancé depuis (la position a bougé) : il revient et est oublié', () {
    final result = applyHiddenResume(
      [_entry('a', const Duration(minutes: 20))],
      {'a': const Duration(minutes: 12).inMilliseconds},
    );
    expect(result.visible.map((e) => e.id), ['a']);
    expect(result.stale, {'a'});
  });

  test('Petit écart de position (arrondi du serveur) : toujours caché', () {
    final result = applyHiddenResume(
      [_entry('a', const Duration(minutes: 12, milliseconds: 900))],
      {'a': const Duration(minutes: 12).inMilliseconds},
    );
    expect(result.visible, isEmpty);
  });

  test('Absent de la liste : retenu (le serveur a pu mal répondre)', () {
    final result = applyHiddenResume(const [], {'a': 1000});
    expect(result.stale, isEmpty);
  });
}
