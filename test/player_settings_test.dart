import 'package:amplyfin/models/playback_speed.dart';
import 'package:amplyfin/models/sleep_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vitesses lisibles', () {
    expect(playbackSpeedLabel(1), 'Normale');
    expect(playbackSpeedLabel(1.25), '× 1,25');
    expect(playbackSpeedLabel(0.5), '× 0,5');
    expect(playbackSpeedLabel(2), '× 2');
    expect(playbackSpeeds, contains(1.0));
  });

  group('minuterie de sommeil', () {
    final now = DateTime(2026, 11, 16, 22);

    test('sans durée : le nom du choix', () {
      expect(sleepTimerStatus(SleepChoice.off, null, now), 'Désactivée');
      expect(
        sleepTimerStatus(SleepChoice.endOfVideo, null, now),
        'À la fin de la vidéo',
      );
    });

    test('temps restant, arrondi à la minute du dessus', () {
      expect(
        sleepTimerStatus(
          SleepChoice.minutes15,
          now.add(const Duration(minutes: 15)),
          now,
        ),
        'Pause dans 15 min',
      );
      expect(
        sleepTimerStatus(
          SleepChoice.hour,
          now.add(const Duration(minutes: 12, seconds: 20)),
          now,
        ),
        'Pause dans 13 min',
      );
      expect(
        sleepTimerStatus(
          SleepChoice.minutes15,
          now.add(const Duration(seconds: 40)),
          now,
        ),
        'Pause dans moins d\'1 min',
      );
    });
  });
}
