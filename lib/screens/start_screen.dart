import 'dart:async';

import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../services/session_store.dart';
import '../theme/app_theme.dart';
import '../widgets/splash_view.dart';
import 'library_screen.dart';
import 'login_screen.dart';

/// Premier écran affiché : le logo animé, pendant qu'on vérifie
/// s'il faut se connecter ou si la session enregistrée est encore valable.
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
    final session = await store.load();

    // Personne n'est connecté : écran de connexion
    if (session == null) return const LoginScreen();

    final api = JellyfinApi(
      serverUrl: session.serverUrl,
      deviceId: await store.deviceId(),
      token: session.accessToken,
    );

    // Le jeton est-il toujours accepté par le serveur ?
    try {
      await api.checkToken();
    } on JellyfinException catch (e) {
      if (e.isUnauthorized) {
        // Jeton révoqué (ex. déconnecté depuis le tableau de bord Jellyfin)
        await store.clear();
        return const LoginScreen();
      }
      // Serveur injoignable pour l'instant : on garde la session quand même
    }

    return LibraryScreen(api: api, session: session);
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
