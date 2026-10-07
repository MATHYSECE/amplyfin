import 'dart:async';

import 'package:flutter/material.dart';

import '../services/device_capabilities.dart';
import '../services/profile_switch.dart';
import '../services/session_store.dart';
import '../theme/app_theme.dart';
import '../widgets/splash_view.dart';
import 'login_screen.dart';
import 'profiles_screen.dart';

/// Premier écran affiché : le logo animé, pendant qu'on choisit l'écran
/// suivant (connexion, « Qui regarde ? » ou le dernier profil).
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  /// Terminé quand l'animation du logo est finie.
  final _animationDone = Completer<void>();

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Vérification et animation en même temps, puis écran suivant.
  Future<void> _start() async {
    final next = await _decide();
    await _animationDone.future;
    _goTo(next);
  }

  /// Écran à ouvrir après le démarrage.
  Future<Widget> _decide() async {
    final store = SessionStore();
    final profiles = await store.profiles();
    final current = await store.load();
    // Tablette : le petit côté de l'écran (ne change pas en tournant)
    final tablet = mounted && MediaQuery.sizeOf(context).shortestSide >= 600;

    // Personne n'est connecté : écran de connexion
    if (profiles.isEmpty) return const LoginScreen();

    // Télé et tablette (partagées) : « Qui regarde ? » ; téléphone : le
    // dernier profil directement
    if (current == null ||
        askWhoIsWatching(tv: DeviceCapabilities.isTv, tablet: tablet)) {
      return const ProfilesScreen();
    }
    return openProfile(current);
  }

  /// Passe à l'écran suivant en fondu.
  void _goTo(Widget screen) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: AppDurations.medium,
        pageBuilder: (_, _, _) => screen,
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SplashView(
        onFinished: () {
          if (!_animationDone.isCompleted) _animationDone.complete();
        },
      ),
    );
  }
}
