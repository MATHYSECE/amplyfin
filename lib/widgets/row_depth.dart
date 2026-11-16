import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/device_capabilities.dart';

/// Effets des rangées d'affiches qui défilent de côté (calculés pendant le
/// dessin, d'après la place de l'affiche à l'écran : rien ne tourne quand
/// on ne fait pas défiler). Pas sur télé.

/// Rangée vue de côté : une affiche qui sort par un bord de l'écran
/// pivote un peu vers l'arrière, rétrécit et pâlit (comme une rangée en
/// arc de cercle).
class RowDepth extends SingleChildRenderObjectWidget {
  const RowDepth({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderRowDepth(_rowPosition(context));

  @override
  void updateRenderObject(BuildContext context, RenderRowDepth renderObject) {
    renderObject.position = _rowPosition(context);
  }
}

/// Reflet de lumière en biais sur une affiche, qui la traverse quand la
/// rangée défile (à poser par-dessus l'affiche, dans un [Stack]).
class PosterSheen extends LeafRenderObjectWidget {
  const PosterSheen({super.key});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPosterSheen(_rowPosition(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPosterSheen renderObject,
  ) {
    renderObject.position = _rowPosition(context);
  }
}

/// Défilement de la rangée qui contient [context] (null hors d'une rangée
/// horizontale, ou sur télé : pas d'effet).
ScrollPosition? _rowPosition(BuildContext context) {
  if (DeviceCapabilities.isTv) return null;
  return Scrollable.maybeOf(context, axis: Axis.horizontal)?.position;
}

/// Redessine l'objet à chaque mouvement de la rangée.
mixin _FollowsRow on RenderObject {
  ScrollPosition? _position;

  set position(ScrollPosition? value) {
    if (value == _position) return;
    if (attached) _position?.removeListener(markNeedsPaint);
    _position = value;
    if (attached) value?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _position?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _position?.removeListener(markNeedsPaint);
    super.detach();
  }

  /// Gauche de l'objet et largeur de la rangée visible (null si inconnues).
  (double, double)? placeInRow(RenderBox box) {
    if (_position == null) return null;
    final Object? viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    final left = box.localToGlobal(Offset.zero, ancestor: viewport).dx;
    return (left, viewport.size.width);
  }
}

/// Dessin de [RowDepth].
class RenderRowDepth extends RenderProxyBox with _FollowsRow {
  RenderRowDepth(ScrollPosition? position) {
    _position = position;
  }

  final _transformLayer = LayerHandle<TransformLayer>();
  final _opacityLayer = LayerHandle<OpacityLayer>();

  @override
  void dispose() {
    _transformLayer.layer = null;
    _opacityLayer.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final place = placeInRow(this);
    // Part de l'affiche sortie de l'écran, à gauche ou à droite (0 à 1)
    var amount = 0.0;
    var leaving = 0;
    if (place != null && size.width > 0) {
      final (left, width) = place;
      final outLeft = -left / size.width;
      final outRight = (left + size.width - width) / size.width;
      if (outLeft > 0) {
        amount = outLeft;
        leaving = -1;
      } else if (outRight > 0) {
        amount = outRight;
        leaving = 1;
      }
    }
    amount = Curves.easeOut.transform(amount.clamp(0.0, 1.0));
    if (amount < 0.002) {
      _transformLayer.layer = null;
      _opacityLayer.layer = null;
      context.paintChild(child, offset);
      return;
    }
    // Pivote autour du bord tourné vers l'écran : le côté qui sort recule
    final pivot = Offset(leaving < 0 ? size.width : 0, size.height / 2);
    // (perspective centrée sur ce bord, sinon l'affiche se déformerait)
    final scale = 1 - 0.08 * amount;
    final transform = Matrix4.translationValues(pivot.dx, pivot.dy, 0)
      ..multiply(Matrix4.identity()..setEntry(3, 2, 0.0011))
      ..multiply(Matrix4.rotationY(-leaving * 0.42 * amount))
      ..multiply(Matrix4.diagonal3Values(scale, scale, 1))
      ..multiply(Matrix4.translationValues(-pivot.dx, -pivot.dy, 0));
    _opacityLayer.layer = context.pushOpacity(
      offset,
      (255 * (1 - 0.55 * amount)).round(),
      (context, offset) {
        _transformLayer.layer = context.pushTransform(
          needsCompositing,
          offset,
          transform,
          (context, offset) => context.paintChild(child, offset),
          oldLayer: _transformLayer.layer,
        );
      },
      oldLayer: _opacityLayer.layer,
    );
  }
}

/// Dessin de [PosterSheen].
class RenderPosterSheen extends RenderBox with _FollowsRow {
  RenderPosterSheen(ScrollPosition? position) {
    _position = position;
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final place = placeInRow(this);
    if (place == null || size.isEmpty) return;
    final (left, width) = place;
    // Milieu de l'affiche : de 0 (bord gauche de l'écran) à 1 (bord droit)
    final across = ((left + size.width / 2) / math.max(width, 1)).clamp(
      -0.2,
      1.2,
    );
    // Le reflet glisse du coin haut gauche au coin bas droit
    final center = -0.25 + across * 1.5;
    final rect = offset & size;
    const band = 0.16;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [Color(0x00FFFFFF), Color(0x1CFFFFFF), Color(0x00FFFFFF)],
        stops: [
          (center - band).clamp(0.0, 1.0),
          center.clamp(0.0, 1.0),
          (center + band).clamp(0.0, 1.0),
        ],
      ).createShader(rect);
    context.canvas.drawRect(rect, paint);
  }
}
