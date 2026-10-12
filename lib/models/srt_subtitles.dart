/// Sous-titres au format SRT (fichier envoyé à part par le serveur),
/// pour les moteurs qui ne lisent pas ceux intégrés au fichier vidéo.
class SrtSubtitles {
  const SrtSubtitles(this.cues);

  /// Lit le texte d'un fichier SRT. Les blocs illisibles sont ignorés.
  factory SrtSubtitles.parse(String text) {
    final cues = <SrtCue>[];
    final blocks = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceFirst('﻿', '')
        .split(RegExp(r'\n\s*\n'));
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      // Ligne des heures : la 1re ou la 2e (après le numéro du bloc)
      final timing = lines.indexWhere((line) => line.contains('-->'));
      if (timing < 0) continue;
      final match = _timing.firstMatch(lines[timing]);
      if (match == null) continue;
      final text = [
        for (final line in lines.skip(timing + 1))
          if (_clean(line).isNotEmpty) _clean(line),
      ];
      if (text.isEmpty) continue;
      cues.add(
        SrtCue(start: _time(match, 1), end: _time(match, 5), lines: text),
      );
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return SrtSubtitles(cues);
  }

  /// Phrases dans l'ordre d'apparition.
  final List<SrtCue> cues;

  /// Lignes à afficher à la position [position] (vide : rien).
  List<String> linesAt(Duration position) => [
    for (final cue in cues)
      if (cue.start <= position && position < cue.end) ...cue.lines,
  ];

  /// « 00:01:02,345 --> 00:01:04,000 » (point accepté à la place de la
  /// virgule, heures sur un ou plusieurs chiffres).
  static final _timing = RegExp(
    r'(\d+):(\d{1,2}):(\d{1,2})[,.](\d{1,3})\s*-->\s*'
    r'(\d+):(\d{1,2}):(\d{1,2})[,.](\d{1,3})',
  );

  static Duration _time(RegExpMatch match, int first) {
    final millis = match[first + 3]!.padRight(3, '0');
    return Duration(
      hours: int.parse(match[first]!),
      minutes: int.parse(match[first + 1]!),
      seconds: int.parse(match[first + 2]!),
      milliseconds: int.parse(millis),
    );
  }

  /// Retire les balises de mise en forme (`<i>`, `<font…>`) et de position
  /// ({\an8}) : notre afficheur a son propre style.
  static String _clean(String line) =>
      line.replaceAll(RegExp(r'<[^>]*>|\{\\[^}]*\}'), '').trim();
}

/// Une phrase : ses lignes, et quand elle apparaît puis disparaît.
class SrtCue {
  const SrtCue({required this.start, required this.end, required this.lines});

  final Duration start;
  final Duration end;
  final List<String> lines;
}
