import 'package:amplyfin/models/tour.dart';
import 'package:amplyfin/screens/tour_screen.dart';
import 'package:amplyfin/services/tour_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('pages de la visite', () {
    test('téléphone : 6 pages, téléchargements en Wi-Fi', () {
      final pages = tourPages(TourDevice.touch);
      expect(pages, hasLength(6));
      final downloads = pages.firstWhere((p) => p.scene == TourScene.downloads);
      expect(downloads.text, contains('Wi-Fi'));
      expect(pages.last.scene, TourScene.profiles);
    });

    test('télé : pas de téléchargements, OK maintenu pour les options', () {
      final pages = tourPages(TourDevice.tv);
      expect(pages, hasLength(5));
      expect(pages.map((p) => p.scene), isNot(contains(TourScene.downloads)));
      expect(pages[1].text, contains('OK maintenu'));
    });

    test('PC : clic droit, et pas de Wi-Fi', () {
      final pages = tourPages(TourDevice.desktop);
      expect(pages, hasLength(6));
      expect(pages[1].text, contains('clic droit'));
      final downloads = pages.firstWhere((p) => p.scene == TourScene.downloads);
      expect(downloads.text, isNot(contains('Wi-Fi')));
    });
  });

  testWidgets('Suivant jusqu\'à Commencer : la visite se ferme, vue', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TourScreen(device: TourDevice.touch),
              ),
            ),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('Bienvenue sur Amplyfin'), findsOneWidget);
    expect(find.text('1 / 6'), findsOneWidget);

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
    }
    expect(find.text('6 / 6'), findsOneWidget);
    // Dernière page : plus de « Passer »
    expect(find.text('Passer'), findsNothing);

    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
    expect(find.byType(TourScreen), findsNothing);
    expect(await TourPreferences().tourSeen(), isTrue);
  });

  testWidgets('Passer ferme la visite et la marque vue', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TourScreen(device: TourDevice.tv),
              ),
            ),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Passer'));
    await tester.pumpAndSettle();
    expect(find.byType(TourScreen), findsNothing);
    expect(await TourPreferences().tourSeen(), isTrue);
  });
}
