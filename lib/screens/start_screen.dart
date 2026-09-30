import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../services/session_store.dart';
import 'library_screen.dart';
import 'login_screen.dart';

/// Premier écran affiché : décide s'il faut se connecter
/// ou si une session enregistrée est encore valable.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final store = SessionStore();
    final session = await store.load();

    // Personne n'est connecté : écran de connexion
    if (session == null) {
      _goTo(const LoginScreen());
      return;
    }

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
        _goTo(const LoginScreen());
        return;
      }
      // Serveur injoignable pour l'instant : on garde la session quand même
    }

    _goTo(LibraryScreen(api: api, session: session));
  }

  void _goTo(Widget screen) {
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
