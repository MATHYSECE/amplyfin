import 'package:amplyfin/theme/app_theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ressort : part de 0, dépasse un peu, finit à 1', () {
    const spring = AppCurves.spring;
    expect(spring.transform(0), 0);
    expect(spring.transform(1), 1);
    final peak = [for (var i = 1; i < 100; i++) spring.transform(i / 100)]
        .reduce((a, b) => a > b ? a : b);
    expect(peak, greaterThan(1));
    expect(peak, lessThan(1.08));
  });

  group('Ambilight', () {
    test('affiche grise : halo blanc (pas de couleur)', () {
      expect(AppColors.ambient(const Color(0xFF808080)), isNull);
      expect(AppColors.ambient(null), isNull);
    });

    test('affiche colorée : même teinte, transparente', () {
      final glow = AppColors.ambient(const Color(0xFF803010), opacity: 0.3)!;
      expect(glow.a, closeTo(0.3, 0.01));
      final hue = HSLColor.fromColor(glow).hue;
      final source = HSLColor.fromColor(const Color(0xFF803010)).hue;
      expect(hue, closeTo(source, 1));
    });
  });
}
