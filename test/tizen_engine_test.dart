import 'package:amplyfin/services/tizen_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Jeton dans l\'adresse (télé Samsung)', () {
    test('le jeton de l\'en-tête est ajouté en ApiKey', () {
      final url = TizenEngine.withToken(
        'https://serveur.test/Videos/abc/stream?static=true',
        {
          'Authorization':
              'MediaBrowser Client="Amplyfin", Device="Samsung%20TV", '
              'DeviceId="x", Version="1.2.0", Token="a1b2c3"',
        },
      );
      final uri = Uri.parse(url);
      expect(uri.path, '/Videos/abc/stream');
      expect(uri.queryParameters['static'], 'true');
      expect(uri.queryParameters['ApiKey'], 'a1b2c3');
    });

    test('sans jeton, l\'adresse reste la même', () {
      const url = 'https://serveur.test/Videos/abc/stream?static=true';
      expect(TizenEngine.withToken(url, const {}), url);
    });
  });
}
