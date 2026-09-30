import 'package:amplyfin/api/jellyfin_api.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests de la fonction qui nettoie l'adresse saisie par l'utilisateur
void main() {
  test('ajoute http:// si absent', () {
    expect(normalizeServerUrl('192.168.1.10:8096'), 'http://192.168.1.10:8096');
  });

  test('garde https:// et retire le / final', () {
    expect(
      normalizeServerUrl(' https://jellyfin.exemple.fr/ '),
      'https://jellyfin.exemple.fr',
    );
  });

  test('garde un éventuel chemin (ex. /jellyfin)', () {
    expect(
      normalizeServerUrl('http://maison.local/jellyfin//'),
      'http://maison.local/jellyfin',
    );
  });

  test('refuse une adresse vide', () {
    expect(() => normalizeServerUrl('   '), throwsFormatException);
  });
}
