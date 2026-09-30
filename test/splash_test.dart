import 'package:amplyfin/theme/app_theme.dart';
import 'package:amplyfin/widgets/splash_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests de l'écran de démarrage animé
void main() {
  testWidgets('l\'animation se joue puis prévient qu\'elle est finie', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: SplashView(onFinished: () => finished = true)),
      ),
    );
    expect(finished, isFalse);

    // Petite attente avant le départ, puis début de l'animation
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(finished, isFalse);

    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(find.text('Amplyfin'), findsOneWidget);
  });

  testWidgets('animations réduites : logo affiché tout de suite', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: SplashView(onFinished: () => finished = true)),
        ),
      ),
    );
    await tester.pump();
    expect(finished, isTrue);
    // Laisse passer la petite attente de départ (sans effet ici)
    await tester.pump(const Duration(milliseconds: 300));
  });

  test('le dessin du logo change avec l\'avancée', () {
    const start = LogoPainter(stroke: 0, play: 0);
    const end = LogoPainter();
    expect(end.shouldRepaint(start), isTrue);
    expect(end.shouldRepaint(const LogoPainter()), isFalse);
  });
}
