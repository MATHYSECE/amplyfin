import 'package:amplyfin/models/tour.dart';
import 'package:amplyfin/widgets/player_tip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(TourDevice device, VoidCallback onDismiss) => MaterialApp(
  home: Scaffold(
    body: PlayerTip(device: device, onDismiss: onDismiss),
  ),
);

void main() {
  testWidgets('Téléphone : les gestes, « Compris » ferme l\'astuce', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(_app(TourDevice.touch, () => dismissed++));
    expect(find.text('Luminosité'), findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
    await tester.tap(find.text('Compris'));
    expect(dismissed, 1);
    // Une seule fois, même après un second appui
    await tester.tap(find.text('Compris'));
    expect(dismissed, 1);
  });

  testWidgets('Télé : les touches, et une touche ferme l\'astuce', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(_app(TourDevice.tv, () => dismissed++));
    expect(find.text('OK maintenu'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(dismissed, 1);
  });

  testWidgets('Disparaît seule au bout de 15 s', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(_app(TourDevice.desktop, () => dismissed++));
    expect(find.text('Espace'), findsOneWidget);
    await tester.pump(const Duration(seconds: 16));
    expect(dismissed, 1);
  });
}
