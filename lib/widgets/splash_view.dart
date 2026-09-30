import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';
import 'ui.dart';

/// Écran de démarrage animé (proposition A « Tracé ») : le « A » se dessine
/// d'un trait, le bouton lecture apparaît avec un petit rebond, puis le nom
/// de l'appli monte en fondu. Tout est dessiné par l'appli (pas de
/// bibliothèque d'animation). Le téléphone affiche un écran noir juste
/// avant : l'animation part de ce noir, sans saut visible.
class SplashView extends StatefulWidget {
  const SplashView({super.key, this.onFinished});

  /// Appelé quand l'animation est terminée.
  final VoidCallback? onFinished;

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 1600);

  /// Attente après la première image : le téléphone passe de son écran de
  /// lancement à l'appli (sinon l'animation se joue sans être vue).
  static const _startDelay = Duration(milliseconds: 250);

  late final _controller = AnimationController(
    vsync: this,
    duration: _duration,
  );

  // Étapes de l'animation (en part de la durée totale)
  late final _stroke = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.5, curve: Curves.easeInOutCubic),
  );
  late final _play = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.42, 0.7, curve: Curves.easeOutBack),
  );
  late final _word = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.6, 0.9, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onFinished?.call();
    });
    _begin();
  }

  /// Lance l'animation une fois l'appli vraiment à l'écran. D'ici là, on
  /// affiche le même noir que l'écran de lancement du téléphone.
  Future<void> _begin() async {
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(_startDelay);
    if (mounted && !_controller.isCompleted) _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Animations réduites dans les réglages du téléphone : logo tout de suite
    if (MediaQuery.disableAnimationsOf(context) && !_controller.isCompleted) {
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
    final wordStyle = Theme.of(context).textTheme.headlineMedium;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          // Le halo apparaît doucement sur le noir du lancement
          Opacity(
            opacity: _stroke.value,
            child: const GlowBackground(child: SizedBox.expand()),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 120,
                  child: CustomPaint(
                    painter: LogoPainter(
                      stroke: _stroke.value,
                      play: _play.value,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Opacity(
                  opacity: _word.value,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - _word.value)),
                    child: Text('Amplyfin', style: wordStyle),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dessine le signe de l'icône (un « A » dont le creux est un bouton
/// lecture), mêmes proportions que assets/icon/icon.svg (repère de 100).
/// [stroke] : part du « A » déjà tracée (0 à 1).
/// [play] : taille du bouton lecture (0 à 1, un peu plus pendant le rebond).
class LogoPainter extends CustomPainter {
  const LogoPainter({this.stroke = 1, this.play = 1});

  final double stroke;
  final double play;

  static final _lambda = Path()
    ..moveTo(26, 79)
    ..lineTo(50, 22)
    ..lineTo(74, 79);

  static final _triangle = Path()
    ..moveTo(45.5, 60)
    ..lineTo(45.5, 75)
    ..lineTo(58, 67.5)
    ..close();

  /// Centre du bouton lecture (point fixe du rebond).
  static const _playCenter = Offset(49.7, 67.5);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);

    // « A » tracé petit à petit
    if (stroke > 0) {
      final line = Paint()
        ..color = AppColors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final metric in _lambda.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * stroke), line);
      }
    }

    // Bouton lecture, qui grossit depuis son centre
    if (play > 0) {
      final fill = Paint()
        ..color = AppColors.white.withValues(alpha: play.clamp(0.0, 1.0))
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round;
      canvas
        ..save()
        ..translate(_playCenter.dx, _playCenter.dy)
        ..scale(play)
        ..translate(-_playCenter.dx, -_playCenter.dy)
        ..drawPath(_triangle, fill..style = PaintingStyle.fill)
        ..drawPath(_triangle, fill..style = PaintingStyle.stroke)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(LogoPainter oldDelegate) =>
      oldDelegate.stroke != stroke || oldDelegate.play != play;
}
