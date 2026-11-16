import 'package:amplyfin/models/blur_hash.dart';
import 'package:amplyfin/models/media_item.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';

  group('Aperçus flous', () {
    test('lus par type puis par empreinte', () {
      final json = {
        'ImageBlurHashes': {
          'Primary': {'tag1': hash},
        },
      };
      expect(blurHashOf(json, 'Primary', 'tag1'), hash);
      expect(blurHashOf(json, 'Primary', 'autre'), isNull);
      expect(blurHashOf(json, 'Backdrop', 'tag1'), isNull);
      expect(blurHashOf(json, 'Primary', null), isNull);
      expect(blurHashOf({}, 'Primary', 'tag1'), isNull);
    });

    test("l'affiche d'un film reçoit son aperçu", () {
      final item = MediaItem.fromJson({
        'Id': 'a',
        'Name': 'Film',
        'ImageTags': {'Primary': 'tag1'},
        'ImageBlurHashes': {
          'Primary': {'tag1': hash},
        },
      });
      expect(item.posterHash, hash);
    });

    test('couleur moyenne', () {
      final color = blurHashAverageColor(hash);
      expect(color, isNotNull);
      expect(color!.a, 1.0);
      expect(blurHashAverageColor('L!!'), isNull);
      expect(blurHashAverageColor('L€€€€€€'), isNull);
    });
  });

  test('couleur moyenne exacte', () {
    // 4 chiffres base 83 « 0001 » = 1 → bleu presque noir
    expect(blurHashAverageColor('00000100'), const Color(0xFF000001));
  });
}
