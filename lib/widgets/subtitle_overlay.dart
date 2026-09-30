import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../models/subtitle_size.dart';
import '../theme/app_theme.dart';

/// Sous-titres dessinés par l'appli, à la place de ceux de media_kit
/// (trop petits sur un téléphone, et fond découpé ligne par ligne) :
/// texte blanc dans une boîte sombre arrondie, comme sur Plex.
/// Ils remontent quand les commandes du lecteur sont affichées, pour ne pas
/// passer sous la barre de progression.
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({
    super.key,
    required this.player,
    required this.size,
    required this.raised,
  });

  /// Hauteur réservée à la barre de progression quand elle est affichée.
  static const _raisedBottom = 96.0;

  final Player player;
  final SubtitleSize size;

  /// Vrai quand les commandes du lecteur sont affichées.
  final ValueListenable<bool> raised;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fontSize = size.fontSizeFor(constraints.biggest.shortestSide);
          final bottom = max(16.0, constraints.maxHeight * 0.06);
          return ValueListenableBuilder<bool>(
            valueListenable: raised,
            builder: (context, isRaised, child) => AnimatedPadding(
              duration: AppDurations.medium,
              curve: Curves.easeOut,
              padding: EdgeInsets.fromLTRB(
                48,
                0,
                48,
                isRaised ? max(bottom, _raisedBottom) : bottom,
              ),
              child: child,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: StreamBuilder<List<String>>(
                stream: player.stream.subtitle,
                initialData: player.state.subtitle,
                builder: (context, snapshot) {
                  final text = joinSubtitleLines(snapshot.data ?? const []);
                  if (text.isEmpty) return const SizedBox.shrink();
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.8,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppSubtitles.box,
                        borderRadius: BorderRadius.circular(
                          AppSubtitles.radius,
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: fontSize * 0.55,
                          vertical: fontSize * 0.18,
                        ),
                        child: Text(
                          text,
                          textAlign: TextAlign.center,
                          // Taille déjà choisie dans le lecteur
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontFamily: AppSubtitles.fontFamily,
                            fontSize: fontSize,
                            fontWeight: AppSubtitles.fontWeight,
                            height: AppSubtitles.lineHeight,
                            color: AppSubtitles.text,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Lignes reçues du lecteur → texte affiché (lignes vides retirées).
String joinSubtitleLines(List<String> lines) => [
  for (final line in lines)
    if (line.trim().isNotEmpty) line.trim(),
].join('\n');
