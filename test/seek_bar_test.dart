import 'package:amplyfin/widgets/seek_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const film = Duration(hours: 2);

  group('Vitesse du repère', () {
    test('lente au début, puis de plus en plus rapide', () {
      final halfSecond = tvSeekDistance(
        const Duration(milliseconds: 500),
        film,
      );
      final oneSecond = tvSeekDistance(const Duration(seconds: 1), film);
      final twoSeconds = tvSeekDistance(const Duration(seconds: 2), film);
      expect(halfSecond, lessThan(60)); // moins d'une minute
      expect(oneSecond - halfSecond, lessThan(twoSeconds - oneSecond));
    });

    test('film de 2 h : les 3/4 atteints en 5 à 6 s', () {
      const threeQuarters = 90 * 60;
      expect(
        tvSeekDistance(const Duration(seconds: 5), film),
        lessThan(threeQuarters),
      );
      expect(
        tvSeekDistance(const Duration(seconds: 6), film),
        greaterThan(threeQuarters),
      );
    });

    test('au maximum : 1/5 de la vidéo par seconde', () {
      final at3 = tvSeekDistance(const Duration(seconds: 3), film);
      final at4 = tvSeekDistance(const Duration(seconds: 4), film);
      expect(at4 - at3, closeTo(film.inSeconds / 5, 0.001));
    });

    test('vidéo courte ou durée inconnue : au moins 1 min par seconde', () {
      final at3 = tvSeekDistance(const Duration(seconds: 3), Duration.zero);
      final at4 = tvSeekDistance(const Duration(seconds: 4), Duration.zero);
      expect(at4 - at3, closeTo(60, 0.001));
    });
  });

  group('Repère de la télé', () {
    late DateTime clock;
    late Duration position;
    late List<Duration> seeks;
    late TvScrubber scrubber;

    setUp(() {
      clock = DateTime(2026);
      position = const Duration(minutes: 10);
      seeks = [];
      scrubber = TvScrubber(
        position: () => position,
        duration: () => film,
        seek: (target) async => seeks.add(target),
        now: () => clock,
      );
    });

    tearDown(() => scrubber.dispose());

    testWidgets('un appui : 10 s, saut une seule fois après le relâchement', (
      tester,
    ) async {
      scrubber.press(1);
      expect(scrubber.target, const Duration(minutes: 10, seconds: 10));
      scrubber.release();
      expect(seeks, isEmpty); // pas tout de suite

      await tester.pump(TvScrubber.commitDelay);
      expect(seeks, [const Duration(minutes: 10, seconds: 10)]);
      expect(scrubber.pending, isFalse);
    });

    testWidgets('appuis rapprochés : ils s\'ajoutent, un seul saut', (
      tester,
    ) async {
      for (var i = 0; i < 3; i++) {
        scrubber.press(-1);
        scrubber.release();
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(seeks, isEmpty);
      await tester.pump(TvScrubber.commitDelay);
      expect(seeks, [const Duration(minutes: 9, seconds: 30)]);
    });

    testWidgets('flèche maintenue : le repère avance selon la durée d\'appui', (
      tester,
    ) async {
      scrubber.press(1);
      // Répétitions toutes les 50 ms pendant 3 s
      for (var ms = 50; ms <= 3000; ms += 50) {
        clock = DateTime(2026).add(Duration(milliseconds: ms));
        scrubber.hold(1);
      }
      final expected =
          const Duration(minutes: 10, seconds: 10).inMilliseconds +
          tvSeekDistance(const Duration(seconds: 3), film) * 1000;
      expect(
        scrubber.target!.inMilliseconds,
        closeTo(expected, 100), // arrondis à la milliseconde
      );
      expect(seeks, isEmpty); // rien tant que la flèche est enfoncée
      scrubber.release();
      await tester.pump(TvScrubber.commitDelay);
      expect(seeks, hasLength(1));
    });

    testWidgets('relâchement perdu : pas de grand saut à l\'appui suivant', (
      tester,
    ) async {
      scrubber.press(1); // jamais relâché
      clock = DateTime(2026).add(const Duration(minutes: 1));
      scrubber.hold(1); // une minute plus tard : comme un appui simple
      expect(scrubber.target, const Duration(minutes: 10, seconds: 20));
      await scrubber.commit();
    });

    testWidgets('OK : saut tout de suite', (tester) async {
      scrubber.press(1);
      await scrubber.commit();
      expect(seeks, [const Duration(minutes: 10, seconds: 10)]);
      await tester.pump(TvScrubber.commitDelay);
      expect(seeks, hasLength(1)); // pas de second saut
    });

    testWidgets('ni avant le début, ni après la fin', (tester) async {
      position = const Duration(seconds: 4);
      scrubber.press(-1);
      expect(scrubber.target, Duration.zero);
      await scrubber.commit();

      position = film - const Duration(seconds: 3);
      scrubber.press(1);
      expect(scrubber.target, film);
      await scrubber.commit();
    });
  });
}
