import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/media_item.dart';
import '../models/session.dart';
import '../services/session_store.dart';
import '../widgets/library_grid.dart';
import 'login_screen.dart';
import 'movie_screen.dart';
import 'series_screen.dart';

/// Bibliothèque : deux onglets, Films et Séries, chacun avec sa grille
/// d'affiches.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.api, required this.session});

  final JellyfinApi api;
  final Session session;

  /// Ouvre la fiche d'un film ou d'une série.
  void _open(BuildContext context, MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => item.isSeries
            ? SeriesScreen(api: api, session: session, series: item)
            : MovieScreen(api: api, session: session, movie: item),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    // On prévient le serveur, mais on se déconnecte même s'il est injoignable
    try {
      await api.logout();
    } on JellyfinException {
      // Rien à faire : le jeton sera de toute façon effacé du téléphone
    }
    if (context.mounted) await _backToLogin(context);
  }

  /// Efface la session du téléphone et revient à l'écran de connexion.
  Future<void> _backToLogin(BuildContext context) async {
    await SessionStore().clear();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    LibraryGrid grid(String type, String emptyMessage) => LibraryGrid(
      api: api,
      session: session,
      itemType: type,
      emptyMessage: emptyMessage,
      onOpen: (item) => _open(context, item),
      onUnauthorized: () => _backToLogin(context),
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Amplyfin'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Se déconnecter',
              onPressed: () => _logout(context),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Films'),
              Tab(text: 'Séries'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            grid('Movie', 'Aucun film trouvé sur ce serveur.'),
            grid('Series', 'Aucune série trouvée sur ce serveur.'),
          ],
        ),
      ),
    );
  }
}
