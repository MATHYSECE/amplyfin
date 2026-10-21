import 'package:amplyfin/models/trailer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bandes-annonces', () {
    test('lue depuis la réponse du serveur', () {
      final trailer = Trailer.fromJson({
        'Id': 'bande1',
        'Name': 'Trailer',
        'RunTimeTicks': 1500000000, // 2 min 30
      });
      expect(trailer.id, 'bande1');
      expect(trailer.runtime, const Duration(minutes: 2, seconds: 30));
    });

    test('nom affiché : numéroté s\'il y en a plusieurs, avec la durée', () {
      const trailer = Trailer(id: 'a', runtime: Duration(seconds: 150));
      expect(trailer.label(1, 1), 'Bande-annonce · 02:30');
      expect(trailer.label(2, 3), 'Bande-annonce 2 · 02:30');
      expect(const Trailer(id: 'b').label(1, 1), 'Bande-annonce');
    });
  });
}
