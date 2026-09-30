import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/session.dart';
import '../services/session_store.dart';
import 'login_screen.dart';

/// Accueil provisoire : sera remplacé par la bibliothèque à l'étape 3.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.api, required this.session});

  final JellyfinApi api;
  final Session session;

  Future<void> _logout(BuildContext context) async {
    // On prévient le serveur, mais on se déconnecte même s'il est injoignable
    try {
      await api.logout();
    } on JellyfinException {
      // Rien à faire : le jeton sera de toute façon effacé du téléphone
    }
    await SessionStore().clear();

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Amplyfin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 64),
              const SizedBox(height: 16),
              Text(
                'Connecté en tant que ${session.userName}',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(session.serverUrl, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              const Text(
                'La bibliothèque arrive à l\'étape 3.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
