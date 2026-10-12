import 'package:amplyfin/models/srt_subtitles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sample =
      '﻿1\r\n'
      '00:00:01,000 --> 00:00:03,500\r\n'
      '<i>Toujours aucune nouvelle</i>\r\n'
      'de Drogon ?\r\n'
      '\r\n'
      '2\r\n'
      '00:00:05,000 --> 00:00:06,000\r\n'
      '{\\an8}En haut\r\n'
      '\r\n';

  test('Lit les phrases, leurs heures et retire les balises', () {
    final srt = SrtSubtitles.parse(sample);
    expect(srt.cues, hasLength(2));
    expect(srt.cues.first.start, const Duration(seconds: 1));
    expect(srt.cues.first.end, const Duration(milliseconds: 3500));
    expect(srt.cues.first.lines, ['Toujours aucune nouvelle', 'de Drogon ?']);
    expect(srt.cues.last.lines, ['En haut']);
  });

  test('Donne les lignes à afficher selon la position', () {
    final srt = SrtSubtitles.parse(sample);
    expect(srt.linesAt(Duration.zero), isEmpty);
    expect(srt.linesAt(const Duration(seconds: 2)), hasLength(2));
    // La fin est exclue : la phrase disparaît à 3,5 s
    expect(srt.linesAt(const Duration(milliseconds: 3500)), isEmpty);
    expect(srt.linesAt(const Duration(milliseconds: 5500)), ['En haut']);
  });

  test('Accepte le point, les heures longues et ignore les blocs abîmés', () {
    final srt = SrtSubtitles.parse(
      '1\n'
      '1:02:03.4 --> 1:02:05.25\n'
      'Bonjour\n'
      '\n'
      'bloc sans heures\n'
      '\n'
      '3\n'
      '00:00:09,000 --> 00:00:10,000\n'
      '\n',
    );
    expect(srt.cues, hasLength(1));
    expect(
      srt.cues.single.start,
      const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 400),
    );
    expect(
      srt.cues.single.end,
      const Duration(hours: 1, minutes: 2, seconds: 5, milliseconds: 250),
    );
  });
}
