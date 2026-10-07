/// Passages repérés dans une vidéo par une extension du serveur (Intro
/// Skipper) : générique de début (« Intro ») et de fin (« Outro »).
/// GET /MediaSegments/{id}.
library;

import 'durations.dart';

/// Un passage : de [start] à [end].
class MediaSegment {
  const MediaSegment({
    required this.type,
    required this.start,
    required this.end,
  });

  /// Lit un passage (réponse du serveur, ou gardé avec un téléchargement).
  static MediaSegment? tryParse(Map<String, dynamic> json) {
    final type = json['Type'] as String?;
    final start = ticksToDuration(json['StartTicks'] as int?);
    final end = ticksToDuration(json['EndTicks'] as int?);
    if (type == null || start == null || end == null || end <= start) {
      return null;
    }
    return MediaSegment(type: type, start: start, end: end);
  }

  /// « Intro », « Outro »…
  final String type;
  final Duration start;
  final Duration end;

  /// Vrai si [position] est dans le passage (moins la dernière seconde :
  /// inutile de proposer de sauter ce qui est presque fini).
  bool contains(Duration position) =>
      position >= start && position < end - const Duration(seconds: 1);

  Map<String, dynamic> toJson() => {
    'Type': type,
    'StartTicks': durationToTicks(start),
    'EndTicks': durationToTicks(end),
  };
}

/// Les passages d'une vidéo (vide : rien de repéré).
class MediaSegments {
  const MediaSegments([this.items = const []]);

  /// Lit une liste de passages (« Items » de la réponse du serveur).
  factory MediaSegments.fromList(List<dynamic>? list) => MediaSegments([
    for (final item in list ?? const [])
      ?MediaSegment.tryParse(item as Map<String, dynamic>),
  ]);

  final List<MediaSegment> items;

  /// Le générique de début (le premier, s'il y en a plusieurs).
  MediaSegment? get intro => _first('Intro');

  /// Début du générique de fin (null s'il n'est pas repéré).
  Duration? get outroStart => _first('Outro')?.start;

  MediaSegment? _first(String type) {
    final matching = items.where((s) => s.type == type).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return matching.firstOrNull;
  }

  List<Map<String, dynamic>> toJson() => [
    for (final item in items) item.toJson(),
  ];
}
