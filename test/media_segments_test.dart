import 'package:amplyfin/models/download_info.dart';
import 'package:amplyfin/models/media_segments.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests des génériques repérés par le serveur (Intro Skipper)
void main() {
  // 1 s = 10 000 000 ticks
  const second = 10000000;

  final segments = MediaSegments.fromList([
    {'Type': 'Outro', 'StartTicks': 1300 * second, 'EndTicks': 1420 * second},
    {'Type': 'Intro', 'StartTicks': 60 * second, 'EndTicks': 150 * second},
    // Passage illisible (fin avant le début) : ignoré
    {'Type': 'Intro', 'StartTicks': 10 * second, 'EndTicks': 5 * second},
  ]);

  test('générique de début et début du générique de fin', () {
    expect(segments.intro?.start, const Duration(seconds: 60));
    expect(segments.intro?.end, const Duration(seconds: 150));
    expect(segments.outroStart, const Duration(seconds: 1300));
  });

  test('pendant l\'intro, sauf la dernière seconde', () {
    final intro = segments.intro!;
    expect(intro.contains(const Duration(seconds: 59)), isFalse);
    expect(intro.contains(const Duration(seconds: 60)), isTrue);
    expect(intro.contains(const Duration(seconds: 148)), isTrue);
    expect(intro.contains(const Duration(milliseconds: 149500)), isFalse);
  });

  test('rien de repéré', () {
    const empty = MediaSegments();
    expect(empty.intro, isNull);
    expect(empty.outroStart, isNull);
  });

  test('gardés avec un téléchargement', () {
    final info = DownloadInfo.fromJson({
      'itemId': 'ep1',
      'name': 'Épisode 1',
      'mediaSourceId': 'ep1',
    }).withSegments(segments);
    final reread = DownloadInfo.fromJson(info.toJson());
    expect(reread.segments.intro?.end, const Duration(seconds: 150));
    expect(reread.segments.outroStart, const Duration(seconds: 1300));
  });
}
