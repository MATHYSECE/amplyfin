import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Mouvements de l'appli : un « ressort » (ça arrive vite, dépasse à peine
/// et se pose) plutôt qu'un mouvement régulier, et le changement d'écran
/// « en profondeur ».

/// Courbe d'un ressort amorti : dépasse un peu la fin (environ 4 %) puis
/// revient s'y poser.
class SpringCurve extends Curve {
  const SpringCurve({this.damping = 0.72, this.stiffness = 11});

  /// Amortissement (1 : sans rebond ; plus petit : rebondit davantage).
  final double damping;

  /// Raideur : plus grand, le ressort se pose plus tôt.
  final double stiffness;

  @override
  double transformInternal(double t) {
    final zeta = damping;
    final omega = stiffness;
    final damped = omega * math.sqrt(1 - zeta * zeta);
    final decay = math.exp(-zeta * omega * t);
    return 1 -
        decay *
            (math.cos(damped * t) +
                (zeta * omega / damped) * math.sin(damped * t));
  }
}

/// Courbes communes.
abstract final class AppCurves {
  /// Ressort léger : appuis relâchés, blocs qui arrivent, écrans qui
  /// s'ouvrent.
  static const spring = SpringCurve();
}

/// Changement d'écran « en profondeur » : le nouvel écran arrive en fondu
/// en grandissant un peu (avec un léger ressort) ; celui de dessous recule
/// et s'assombrit. Au retour, l'inverse, sans rebond.
class DepthPageTransitionsBuilder extends PageTransitionsBuilder {
  const DepthPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 560);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(
      parent: animation,
      curve: AppCurves.spring,
      reverseCurve: Curves.easeInCubic,
    );
    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.4, curve: Curves.easeOut),
      reverseCurve: const Interval(0.2, 1, curve: Curves.easeIn),
    );
    final behind = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return ScaleTransition(
      // Écran de dessous : recule un peu
      scale: Tween(begin: 1.0, end: 0.94).animate(behind),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: Tween(begin: 0.92, end: 1.0).animate(enter),
              child: child,
            ),
          ),
          // … et s'assombrit
          IgnorePointer(
            child: FadeTransition(
              opacity: Tween(begin: 0.0, end: 0.6).animate(behind),
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}
