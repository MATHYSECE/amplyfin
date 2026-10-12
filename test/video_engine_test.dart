import 'dart:async';

import 'package:amplyfin/models/subtitle_size.dart';
import 'package:amplyfin/services/video_engine.dart';
import 'package:amplyfin/widgets/subtitle_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faux moteur : seuls l'état et les sous-titres servent ici.
class _FakeEngine implements VideoEngine {
  final subtitles = StreamController<List<String>>.broadcast(sync: true);

  @override
  EngineState get state => const EngineState();

  @override
  late final EngineStreams stream = EngineStreams(
    position: const Stream.empty(),
    playing: const Stream.empty(),
    buffering: const Stream.empty(),
    completed: const Stream.empty(),
    subtitle: subtitles.stream,
    errors: const Stream.empty(),
    decodeFailures: const Stream.empty(),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Les sous-titres affichés viennent du moteur, quel qu\'il soit', (
    tester,
  ) async {
    final engine = _FakeEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: SubtitleOverlay(
          player: engine,
          size: SubtitleSize.standard,
          raised: ValueNotifier(false),
        ),
      ),
    );
    expect(find.text('Bonjour'), findsNothing);

    engine.subtitles.add(['Bonjour']);
    await tester.pump();
    expect(find.text('Bonjour'), findsOneWidget);

    engine.subtitles.add(const []);
    await tester.pump();
    expect(find.text('Bonjour'), findsNothing);
    await engine.subtitles.close();
  });
}
