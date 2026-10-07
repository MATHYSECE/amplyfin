import 'package:amplyfin/models/subtitle_size.dart';
import 'package:amplyfin/services/player_preferences.dart';
import 'package:amplyfin/widgets/subtitle_overlay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Tests de l'affichage des sous-titres
void main() {
  group('Taille des sous-titres', () {
    test('proportionnelle à la hauteur de l\'image', () {
      // Téléphone à l'horizontale (390 de haut) : environ 18
      expect(SubtitleSize.medium.fontSizeFor(390), closeTo(18.3, 0.1));
      expect(
        SubtitleSize.extraSmall.fontSizeFor(390),
        lessThan(SubtitleSize.small.fontSizeFor(390)),
      );
      expect(
        SubtitleSize.small.fontSizeFor(390),
        lessThan(SubtitleSize.medium.fontSizeFor(390)),
      );
      expect(
        SubtitleSize.large.fontSizeFor(390),
        greaterThan(SubtitleSize.medium.fontSizeFor(390)),
      );
    });

    test('« Très petite » en tête du menu, « Petite » par défaut', () {
      expect(SubtitleSize.values.first, SubtitleSize.extraSmall);
      expect(SubtitleSize.standard, SubtitleSize.small);
    });

    test('taille enregistrée inconnue ou absente : petite', () {
      expect(SubtitleSize.fromName('large'), SubtitleSize.large);
      expect(SubtitleSize.fromName('extraSmall'), SubtitleSize.extraSmall);
      expect(SubtitleSize.fromName('géante'), SubtitleSize.small);
      expect(SubtitleSize.fromName(null), SubtitleSize.small);
    });

    test('retenue sur le téléphone', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PlayerPreferences();
      expect(await preferences.loadSubtitleSize(), SubtitleSize.small);
      await preferences.saveSubtitleSize(SubtitleSize.extraSmall);
      expect(await preferences.loadSubtitleSize(), SubtitleSize.extraSmall);
    });
  });

  group('Texte affiché', () {
    test('lignes vides retirées, espaces en trop enlevés', () {
      expect(
        joinSubtitleLines([' Regarde. ', '', 'Il pleut.  ']),
        'Regarde.\nIl pleut.',
      );
    });

    test('rien à afficher', () {
      expect(joinSubtitleLines(['', '  ']), isEmpty);
      expect(joinSubtitleLines([]), isEmpty);
    });
  });
}
