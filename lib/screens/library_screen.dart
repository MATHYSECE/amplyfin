import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/media_item.dart';
import '../models/resume_entry.dart';
import '../models/session.dart';
import '../models/track_choice.dart';
import '../services/playback_launcher.dart';
import '../services/session_store.dart';
import '../services/track_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/continue_watching.dart';
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

  /// Films et épisodes commencés (rangée « Continuer à regarder »).
  List<ResumeEntry> _resume = const [];

  /// Vrai pendant le lancement d'une lecture depuis la rangée.
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _loadResume();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Demande au serveur ce qui est en cours. En cas d'erreur, on garde
  /// l'ancienne rangée (la grille affiche déjà le problème de connexion).
  Future<void> _loadResume() async {
    try {
      final entries = await widget.api.getResumeItems(
        userId: widget.session.userId,
      );
      if (mounted) setState(() => _resume = entries);
    } on JellyfinException {
      // Rien à faire : la rangée sera mise à jour la prochaine fois
    }
  }

  /// Appui long sur une affiche de la rangée : reprendre, depuis le début,
  /// aller à la fiche, ou retirer de la rangée.
  Future<void> _showResumeOptions(ResumeEntry entry) async {
    final action = await showResumeActions(context, entry);
    if (!mounted) return;
    switch (action) {
      case ResumeAction.resume:
        await _playResume(entry);
      case ResumeAction.restart:
        await _playResume(entry, start: Duration.zero);
      case ResumeAction.openDetails:
        // Fiche du film, ou de la série ouverte sur la saison de l'épisode
        await _open(entry.poster, seasonId: entry.seasonId);
      case ResumeAction.remove:
        await _removeResume(entry);
      case null:
        break;
    }
  }

  /// Efface la progression d'un film ou d'un épisode (comme jamais regardé) :
  /// il disparaît tout de suite de la rangée, avec « Annuler » quelques
  /// secondes pour remettre la position d'avant.
  Future<void> _removeResume(ResumeEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(
      () => _resume = [
        for (final other in _resume)
          if (other.id != entry.id) other,
      ],
    );
    try {
      await widget.api.updateWatchProgress(
        userId: widget.session.userId,
        itemId: entry.id,
        position: Duration.zero,
        played: false,
      );
    } on JellyfinException catch (e) {
      // Échec : la rangée revient comme avant
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      await _loadResume();
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Retiré de Continuer à regarder'),
        action: SnackBarAction(
          label: 'Annuler',
          textColor: AppColors.white,
          onPressed: () => _undoRemove(entry),
        ),
      ),
    );
  }

  /// « Annuler » : remet la position d'avant, puis recharge la rangée.
  Future<void> _undoRemove(ResumeEntry entry) async {
    try {
      await widget.api.updateWatchProgress(
        userId: widget.session.userId,
        itemId: entry.id,
        position: entry.progress.position,
        played: entry.progress.played,
      );
    } on JellyfinException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    await _loadResume();
  }

  /// Reprend la lecture d'un film ou d'un épisode de la rangée
  /// (ou à la position [start] si elle est précisée).
  Future<void> _playResume(ResumeEntry entry, {Duration? start}) async {
    if (_starting) return;
    _starting = true;
    // Épisode : les langues choisies pour sa série
    var tracks = const TrackSelection();
    final seriesId = entry.seriesId;
    if (seriesId != null) {
      final languages = await TrackPreferences().load(seriesId);
      tracks = languages.resolve(entry.tracks);
    }
    if (!mounted) return;
    await launchPlayback(
      context,
      api: widget.api,
      session: widget.session,
      itemId: entry.id,
      title: entry.playerTitle,
      subtitle: entry.playerSubtitle,
      tracks: tracks,
      start: start ?? entry.progress.position,
    );
    _starting = false;
    await _loadResume();
  }

  /// Ouvre la fiche d'un film ou d'une série. Au retour, la rangée
  /// « Continuer à regarder » est mise à jour.
  /// [seasonId] : saison sur laquelle ouvrir une série.
  Future<void> _open(MediaItem item, {String? seasonId}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => item.isSeries
            ? SeriesScreen(
                api: widget.api,
                session: widget.session,
                series: item,
                initialSeasonId: seasonId,
              )
            : MovieScreen(
                api: widget.api,
                session: widget.session,
                movie: item,
              ),
      ),
    );
    await _loadResume();
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

    LibraryGrid grid(String type, String emptyMessage, String gridTitle) =>
        LibraryGrid(
          api: widget.api,
          session: widget.session,
          itemType: type,
          emptyMessage: emptyMessage,
          topPadding: headerHeight,
          onOpen: _open,
          onUnauthorized: _backToLogin,
          onRefresh: _loadResume,
          // Rangée « Continuer à regarder », seulement s'il y a du contenu
          header: _resume.isEmpty
              ? null
              : ContinueWatchingRow(
                  api: widget.api,
                  entries: _resume,
                  gridTitle: gridTitle,
                  onPlay: _playResume,
                  onOptions: _showResumeOptions,
                ),
        );

    return Scaffold(
      body: GlowBackground(
        child: Stack(
          children: [
            TabBarView(
              controller: _tabs,
              children: [
                grid(
                  'Movie',
                  'Aucun film trouvé sur ce serveur.',
                  'Tous les films',
                ),
                grid(
                  'Series',
                  'Aucune série trouvée sur ce serveur.',
                  'Toutes les séries',
                ),
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
