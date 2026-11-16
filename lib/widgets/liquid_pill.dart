import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Pastille « liquide » sous l'onglet choisi (à poser dans un [Stack]) :
/// quand l'onglet change, son bord avant part d'abord, l'arrière suit avec
/// un peu de retard, comme une goutte qui s'étire puis se rétracte avec un
/// léger rebond. Elle s'aplatit un peu quand elle s'étire.
class LiquidPill extends StatefulWidget {
  const LiquidPill({
    super.key,
    required this.index,
    required this.slotExtent,
    required this.pillExtent,
    required this.crossStart,
    required this.crossExtent,
    this.axis = Axis.horizontal,
    this.mainStart = 0,
    this.radius = AppRadius.pill,
  });

  /// Onglet choisi.
  final int index;

  /// Place prise par chaque onglet, dans le sens de la barre.
  final double slotExtent;

  /// Longueur de la pastille au repos (centrée dans son onglet).
  final double pillExtent;

  /// Position et épaisseur de la pastille dans l'autre sens.
  final double crossStart;
  final double crossExtent;

  /// Barre horizontale (en bas) ou verticale (menu de la télé).
  final Axis axis;

  /// Début du premier onglet, dans le sens de la barre.
  final double mainStart;
  final double radius;

  @override
  State<LiquidPill> createState() => _LiquidPillState();
}

class _LiquidPillState extends State<LiquidPill>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    value: 1,
  );

  /// Bords de départ et d'arrivée de la pastille (dans le sens de la barre).
  late double _fromStart = _startFor(widget.index);
  late double _fromEnd = _fromStart + widget.pillExtent;
  late double _toStart = _fromStart;

  // Bord avant : part tout de suite ; bord arrière : part en retard et
  // dépasse un peu à l'arrivée (rebond)
  static const _lead = Interval(0, 0.62, curve: Curves.easeOutCubic);
  static const _lag = Interval(0.16, 1, curve: Curves.easeOutBack);

  double _startFor(int index) =>
      widget.mainStart +
      index * widget.slotExtent +
      (widget.slotExtent - widget.pillExtent) / 2;

  /// Bords de la pastille à cet instant.
  (double, double) get _edges {
    final t = _controller.value;
    final toEnd = _toStart + widget.pillExtent;
    final forward = _toStart >= _fromStart;
    final startT = (forward ? _lag : _lead).transform(t);
    final endT = (forward ? _lead : _lag).transform(t);
    return (
      lerpDouble(_fromStart, _toStart, startT)!,
      lerpDouble(_fromEnd, toEnd, endT)!,
    );
  }

  @override
  void didUpdateWidget(LiquidPill old) {
    super.didUpdateWidget(old);
    final target = _startFor(widget.index);
    if (old.index != widget.index) {
      // Repart de là où elle est (même au milieu d'un mouvement)
      final (start, end) = _edges;
      _fromStart = start;
      _fromEnd = end;
      _toStart = target;
      _controller.forward(from: 0);
    } else if (target != _toStart || old.pillExtent != widget.pillExtent) {
      // Taille de la barre changée (rotation, fenêtre) : pas d'animation
      _fromStart = _toStart = target;
      _fromEnd = target + widget.pillExtent;
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final (start, end) = _edges;
        final length = math.max(end - start, 1.0);
        // S'étire → s'aplatit un peu ; se tasse au rebond → s'épaissit
        final stretch = length / widget.pillExtent;
        final thickness =
            widget.crossExtent * (1 / math.sqrt(stretch)).clamp(0.72, 1.1);
        final cross = widget.crossStart + (widget.crossExtent - thickness) / 2;
        return widget.axis == Axis.horizontal
            ? Positioned(
                left: start,
                width: length,
                top: cross,
                height: thickness,
                child: child!,
              )
            : Positioned(
                top: start,
                height: length,
                left: cross,
                width: thickness,
                child: child!,
              );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}
