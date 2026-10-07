import 'package:amplyfin/services/device_capabilities.dart';
import 'package:amplyfin/widgets/tv_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Ces tests font comme si l'appli tournait sur une télé
  setUp(() {
    DeviceCapabilities.isTv = true;
    ignoreTvOkRepeats(); // comme au démarrage de l'appli sur télé
  });
  tearDown(() => DeviceCapabilities.isTv = false);

  Future<void> pressOk(WidgetTester tester, Duration hold) async {
    await simulateKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(hold);
    await simulateKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
  }

  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('OK court : appui normal, au relâchement', (tester) async {
    var taps = 0;
    var menus = 0;
    await tester.pumpWidget(
      app(
        TvFocusable(
          autofocus: true,
          onTap: () => taps++,
          onMenu: () => menus++,
          child: const SizedBox(width: 50, height: 50),
        ),
      ),
    );
    await tester.pump();

    await simulateKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 100));
    expect(taps, 0); // pas encore relâché
    await simulateKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(taps, 1);
    expect(menus, 0);
  });

  testWidgets('OK maintenu : options, sans appui normal', (tester) async {
    var taps = 0;
    var menus = 0;
    await tester.pumpWidget(
      app(
        TvFocusable(
          autofocus: true,
          onTap: () => taps++,
          onMenu: () => menus++,
          child: const SizedBox(width: 50, height: 50),
        ),
      ),
    );
    await tester.pump();

    await pressOk(tester, tvLongPressDelay + const Duration(milliseconds: 100));

    expect(menus, 1);
    expect(taps, 0);
  });

  testWidgets('Sans appui long : OK réagit dès l\'appui', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      app(
        TvFocusable(
          autofocus: true,
          onTap: () => taps++,
          child: const SizedBox(width: 50, height: 50),
        ),
      ),
    );
    await tester.pump();

    await simulateKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(taps, 1);
    await simulateKeyUpEvent(LogicalKeyboardKey.select);
  });

  testWidgets('OK gardé après l\'appui long : le menu ouvert ne réagit pas', (
    tester,
  ) async {
    final menuButton = FocusNode();
    addTearDown(menuButton.dispose);
    var menuButtonTaps = 0;
    await tester.pumpWidget(
      app(
        Column(
          children: [
            TvFocusable(
              autofocus: true,
              onTap: () {},
              // L'appui long sélectionne le bouton du « menu »
              onMenu: menuButton.requestFocus,
              child: const SizedBox(width: 50, height: 50),
            ),
            TvFocusable(
              focusNode: menuButton,
              onTap: () => menuButtonTaps++,
              child: const SizedBox(width: 50, height: 50),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    await simulateKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(tvLongPressDelay + const Duration(milliseconds: 100));
    expect(menuButton.hasPrimaryFocus, isTrue);

    // La télécommande répète OK tant qu'on ne relâche pas
    await simulateKeyRepeatEvent(LogicalKeyboardKey.select);
    await simulateKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(menuButtonTaps, 0);

    // Un nouvel appui sur OK marche normalement
    await pressOk(tester, Duration.zero);
    expect(menuButtonTaps, 1);
  });

  testWidgets('OK gardé sur une affiche sans options : la fiche ouverte '
      'ne lance pas la lecture', (tester) async {
    final playButton = FocusNode();
    addTearDown(playButton.dispose);
    var plays = 0;
    await tester.pumpWidget(
      app(
        Column(
          children: [
            // L'affiche « ouvre la fiche » : sélectionne le bouton Lecture
            TvFocusable(
              autofocus: true,
              onTap: playButton.requestFocus,
              child: const SizedBox(width: 50, height: 50),
            ),
            TvFocusable(
              focusNode: playButton,
              onTap: () => plays++,
              child: const SizedBox(width: 50, height: 50),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    await simulateKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(playButton.hasPrimaryFocus, isTrue);
    await simulateKeyRepeatEvent(LogicalKeyboardKey.select);
    await simulateKeyRepeatEvent(LogicalKeyboardKey.select);
    await simulateKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(plays, 0);
  });
}
