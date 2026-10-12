import 'package:amplyfin/services/app_window.dart';
import 'package:amplyfin/services/device_capabilities.dart';
import 'package:amplyfin/widgets/ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Ces tests font comme si l'appli tournait sur un PC
  setUp(() => DeviceCapabilities.isDesktop = true);
  tearDown(() {
    DeviceCapabilities.isDesktop = false;
    AppWindow.fullScreen.value = false;
  });

  Widget app(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('Affiche : clic droit = options, clic gauche = ouvrir', (
    tester,
  ) async {
    var taps = 0;
    var menus = 0;
    await tester.pumpWidget(
      app(
        PressableScale(
          onTap: () => taps++,
          onLongPress: () => menus++,
          child: const SizedBox(width: 80, height: 120),
        ),
      ),
    );

    await tester.tap(find.byType(PressableScale), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(menus, 1);
    expect(taps, 0);

    await tester.tap(find.byType(PressableScale));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('Plein écran : demandé au code natif, puis retenu', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('amplyfin/window'),
      (call) async {
        calls.add(call);
        return null;
      },
    );

    await AppWindow.toggleFullScreen();
    expect(AppWindow.fullScreen.value, isTrue);
    await AppWindow.setFullScreen(true); // déjà en plein écran : rien
    await AppWindow.toggleFullScreen();
    expect(AppWindow.fullScreen.value, isFalse);

    expect(calls.map((c) => c.arguments), [true, false]);
  });

  testWidgets('Plein écran : sans effet hors PC', (tester) async {
    DeviceCapabilities.isDesktop = false;
    await AppWindow.toggleFullScreen();
    expect(AppWindow.fullScreen.value, isFalse);
  });
}
