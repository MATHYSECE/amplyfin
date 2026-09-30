import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/media_item.dart';
import '../models/session.dart';
import '../services/session_store.dart';
import '../theme/app_theme.dart';
import '../widgets/library_grid.dart';
import '../widgets/ui.dart';
import 'login_screen.dart';
import 'movie_screen.dart';
import 'series_screen.dart';

/// Bibliothèque : titre, onglets Films / Séries en pilule, et une grille
/// d'affiches par onglet qui défile sous un en-tête en verre dépoli.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.api, required this.session});

  final JellyfinApi api;
  final Session session;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Ouvre la fiche d'un film ou d'une série.
  void _open(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => item.isSeries
            ? SeriesScreen(
                api: widget.api,
                session: widget.session,
                series: item,
              )
            : MovieScreen(
                api: widget.api,
                session: widget.session,
                movie: item,
              ),
      ),
    );
  }

  Future<void> _logout() async {
    // On prévient le serveur, mais on se déconnecte même s'il est injoignable
    try {
      await widget.api.logout();
    } on JellyfinException {
      // Rien à faire : le jeton sera de toute façon effacé du téléphone
    }
    await _backToLogin();
  }

  /// Efface la session du téléphone et revient à l'écran de connexion.
  Future<void> _backToLogin() async {
    await SessionStore().clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    // Hauteur de l'en-tête : les grilles commencent juste en dessous
    final headerHeight = topInset + 132;

    LibraryGrid grid(String type, String emptyMessage) => LibraryGrid(
      api: widget.api,
      session: widget.session,
      itemType: type,
      emptyMessage: emptyMessage,
      topPadding: headerHeight,
      onOpen: _open,
      onUnauthorized: _backToLogin,
    );

    return Scaffold(
      body: GlowBackground(
        child: Stack(
          children: [
            TabBarView(
              controller: _tabs,
              children: [
                grid('Movie', 'Aucun film trouvé sur ce serveur.'),
                grid('Series', 'Aucune série trouvée sur ce serveur.'),
              ],
            ),
            // En-tête en verre dépoli : les affiches défilent dessous
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    height: headerHeight,
                    padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppColors.scrim70, AppColors.scrim35],
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Amplyfin',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                            ),
                            GlassCircleButton(
                              icon: Icons.logout_rounded,
                              tooltip: 'Se déconnecter',
                              onPressed: _logout,
                            ),
                          ],
                        ),
                        const Spacer(),
                        PillTabs(
                          controller: _tabs,
                          labels: const ['Films', 'Séries'],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
