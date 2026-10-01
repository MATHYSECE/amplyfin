import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';

/// Écran qui s'ouvre en cercle à partir d'un point (ex. le bouton qui l'a
/// ouvert), et s'y referme au retour.
class CircleRevealRoute<T> extends PageRouteBuilder<T> {
  CircleRevealRoute({required WidgetBuilder builder, required Offset center})
    : super(
        transitionDuration: AppDurations.emphasized + AppDurations.fast,
        reverseTransitionDuration: AppDurations.emphasized,
        pageBuilder: (context, _, _) => builder(context),
        transitionsBuilder: (context, animation, _, child) {
          final curve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubicEmphasized,
            reverseCurve: Curves.easeInCubic,
          );
          return AnimatedBuilder(
            animation: curve,
            builder: (context, child) => ClipPath(
              clipper: _CircleClipper(center: center, fraction: curve.value),
              child: child,
            ),
            child: child,
          );
        },
      );
}

class _CircleClipper extends CustomClipper<Path> {
  const _CircleClipper({required this.center, required this.fraction});

  final Offset center;
  final double fraction;

  @override
  Path getClip(Size size) {
    // Rayon final : jusqu'au coin le plus éloigné de l'écran
    final far = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((corner) => (corner - center).distance).reduce(math.max);
    final radius = 22 + (far - 22) * fraction;
    return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  bool shouldReclip(_CircleClipper old) =>
      old.fraction != fraction || old.center != center;
}

/// Zone dont les éléments [MoveAnimated] glissent vers leur nouvelle place
/// quand la liste change (au lieu de sauter), et dont les nouveaux
/// éléments apparaissent en fondu.
class MoveScope extends StatefulWidget {
  const MoveScope({super.key, required this.child});

  final Widget child;

  @override
  State<MoveScope> createState() => _MoveScopeState();
}

class _MoveScopeState extends State<MoveScope> {
  final _boxKey = GlobalKey();

  /// Faux pendant la première image : la liste de départ ne s'anime pas.
  bool ready = false;

  RenderObject? get box => _boxKey.currentContext?.findRenderObject();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ready = true);
  }

  @override
  Widget build(BuildContext context) {
    return _MoveScopeMarker(
      scope: this,
      child: KeyedSubtree(key: _boxKey, child: widget.child),
    );
  }
}

class _MoveScopeMarker extends InheritedWidget {
  const _MoveScopeMarker({required this.scope, required super.child});

  final _MoveScopeState scope;

  @override
  bool updateShouldNotify(_MoveScopeMarker old) => false;
}

/// Élément d'une liste dans un [MoveScope] : quand sa place change (un
/// téléchargement terminé passe de « En cours » à « Films », une ligne
/// au-dessus disparaît…), il glisse de l'ancienne place à la nouvelle.
/// Lui donner une clé (`ValueKey`) pour qu'il soit reconnu d'une fois sur
/// l'autre.
class MoveAnimated extends StatefulWidget {
  const MoveAnimated({super.key, required this.child});

  final Widget child;

  @override
  State<MoveAnimated> createState() => _MoveAnimatedState();
}

class _MoveAnimatedState extends State<MoveAnimated>
    with TickerProviderStateMixin {
  late final _move = AnimationController(
    vsync: this,
    duration: AppDurations.emphasized,
    value: 1,
  )..addListener(() => _render?.markNeedsPaint());
  late final _moveCurve = CurvedAnimation(
    parent: _move,
    curve: Curves.easeInOutCubicEmphasized,
  );

  /// Apparition en fondu (seulement pour un élément ajouté après coup).
  AnimationController? _enter;

  _MoveScopeState? _scope;
  _RenderMove? _render;

  /// Dernière place connue dans la liste, et décalage en cours.
  Offset? _lastPosition;
  Offset _delta = Offset.zero;

  /// Vrai entre le changement de place et le départ de l'animation.
  bool _pending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scope != null) return;
    _scope = context.getInheritedWidgetOfExactType<_MoveScopeMarker>()?.scope;
    if (_scope?.ready ?? false) {
      _enter = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 380),
      )..forward();
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _enter?.dispose();
    super.dispose();
  }

  /// Décalage à appliquer au dessin, à cet instant.
  Offset get _offset => _pending ? _delta : _delta * (1 - _moveCurve.value);

  /// Appelé à chaque dessin avec la place de l'élément dans la liste.
  void _place(Offset position) {
    final last = _lastPosition;
    if (last != null && (position - last).distanceSquared > 0.25) {
      // L'élément reste visuellement où il était, puis glisse
      _delta = last + _offset - position;
      _pending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pending = false;
        _move.forward(from: 0);
      });
    }
    _lastPosition = position;
  }

  @override
  Widget build(BuildContext context) {
    var child = widget.child;
    final enter = _enter;
    if (enter != null) {
      final curve = CurvedAnimation(parent: enter, curve: Curves.easeOutCubic);
      child = FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(curve),
          child: child,
        ),
      );
    }
    return _MoveBox(state: this, child: child);
  }
}

class _MoveBox extends SingleChildRenderObjectWidget {
  const _MoveBox({required this.state, super.child});

  final _MoveAnimatedState state;

  @override
  _RenderMove createRenderObject(BuildContext context) => _RenderMove(state);

  @override
  void updateRenderObject(BuildContext context, _RenderMove renderObject) {
    renderObject.state = state;
  }
}

class _RenderMove extends RenderProxyBox {
  _RenderMove(_MoveAnimatedState state) : _state = state {
    state._render = this;
  }

  _MoveAnimatedState _state;
  set state(_MoveAnimatedState value) {
    _state = value;
    value._render = this;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final box = _state._scope?.box;
    if (box != null && box.attached && attached) {
      _state._place(
        MatrixUtils.transformPoint(getTransformTo(box), Offset.zero),
      );
    }
    final child = this.child;
    if (child != null) context.paintChild(child, offset + _state._offset);
  }
}

/// Retour à l'écran précédent en glissant le doigt depuis le bord gauche
/// (pour les écrans ouverts sans l'animation habituelle, qui n'ont pas ce
/// geste d'office sur iPhone).
class EdgeSwipeBack extends StatefulWidget {
  const EdgeSwipeBack({super.key, required this.child});

  final Widget child;

  @override
  State<EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<EdgeSwipeBack> {
  double _distance = 0;

  @override
  Widget build(BuildContext context) {
    // Prend tout l'écran (le fond aussi, même si le contenu est court)
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 20,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _distance = 0,
            onHorizontalDragUpdate: (details) => _distance += details.delta.dx,
            onHorizontalDragEnd: (details) {
              final fast = (details.primaryVelocity ?? 0) > 400;
              if (_distance > 80 || (fast && _distance > 20)) {
                Navigator.of(context).maybePop();
              }
            },
          ),
        ),
      ],
    );
  }
}
