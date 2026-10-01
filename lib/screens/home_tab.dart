import 'dart:async';

import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/home_items.dart';
import '../models/media_item.dart';
import '../models/resume_entry.dart';
import '../models/session.dart';
import '../models/track_choice.dart';
import '../services/connection_monitor.dart';
import '../services/download_groups.dart';
import '../services/download_manager.dart';
import '../services/offline_progress.dart';
import '../services/playback_launcher.dart';
import '../services/track_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/continue_watching.dart';
import '../widgets/download_rows.dart';
import '../widgets/home_hero.dart';
import '../widgets/media_row.dart';
import '../widgets/ui.dart';
import 'downloads_screen.dart';
import 'movie_screen.dart';
import 'series_screen.dart';
import 'sorted_items_screen.dart';

/// Onglet Accueil : « À la une », puis Continuer à regarder, Films ajoutés
/// récemment, Nouveaux épisodes, Sortis récemment et Téléchargés. Une
/// rangée vide n'est pas affichée. Sans serveur : un message, et les
/// téléchargements.
class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.api,
    required this.session,
    required this.controller,
    required this.headerHeight,
    required this.bottomPadding,
    required this.onUnauthorized,
  });

  final JellyfinApi api;
  final Session session;
  final ScrollController controller;

  /// Hauteur de l'en-tête qui passe par-dessus le contenu.
  final double headerHeight;

  /// Espace laissé en bas pour la barre de navigation.
  final double bottomPadding;

  /// Le serveur refuse le jeton : retour à la connexion.
  final VoidCallback onUnauthorized;

  @override
  State<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends State<HomeTab> {
  bool _loading = true;

  /// Vrai si aucune rangée n'a pu être chargée (serveur injoignable).
  bool _failed = false;

  List<HeroItem> _hero = const [];
  List<ResumeEntry> _continue = const [];
  List<Map<String, dynamic>> _latestMovies = const [];
  List<NewEpisodesEntry> _newEpisodes = const [];
  List<MediaItem> _released = const [];

  /// Vrai pendant le lancement d'une lecture.
  bool _starting = false;

  String get _userId => widget.session.userId;

  @override
  void initState() {
    super.initState();
    _load();
    ConnectionMonitor.instance.addListener(_onConnection);
  }

  @override
  void dispose() {
    ConnectionMonitor.instance.removeListener(_onConnection);
    super.dispose();
  }

  /// La connexion revient : l'accueil se remplit.
  void _onConnection() {
    if (_failed && ConnectionMonitor.instance.online) _load();
  }

  /// Fait une demande sans jamais échouer : en cas d'erreur, null (la
  /// rangée ne s'affiche pas) ; jeton refusé : retour à la connexion.
  Future<T?> _safe<T>(Future<T> request) async {
    try {
      return await request;
    } on JellyfinException catch (e) {
      if (e.isUnauthorized && mounted) widget.onUnauthorized();
      return null;
    }
  }

  /// Charge toutes les rangées en même temps.
  Future<void> _load() async {
    final now = DateTime.now();
    final continueFuture = _fetchContinue();
    final moviesFuture = _safe(
      widget.api.getLatest(userId: _userId, types: 'Movie'),
    );
    final episodesFuture = _safe(
      widget.api.getLatest(userId: _userId, types: 'Episode', groupItems: true),
    );
    final releasedFuture = _safe(
      widget.api.getItems(
        userId: _userId,
        type: 'Movie',
        limit: 16,
        sortBy: 'PremiereDate',
        releasedBefore: now,
      ),
    );
    final continueEntries = await continueFuture;
    final movies = await moviesFuture;
    final episodes = await episodesFuture;
    final released = await releasedFuture;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed =
          continueEntries == null &&
          movies == null &&
          episodes == null &&
          released == null;
      _continue = continueEntries ?? const [];
      _latestMovies = movies ?? const [];
      _newEpisodes = [
        for (final json in episodes ?? const <Map<String, dynamic>>[])
          NewEpisodesEntry.fromLatestJson(json),
      ];
      _released = released?.items ?? const [];
      _hero = pickHeroItems(movies ?? const [], episodes ?? const []);
    });
  }

  /// « Continuer à regarder » : commencés + épisodes suivants, mélangés du
  /// plus récent au plus ancien (null si le serveur ne répond pas).
  Future<List<ResumeEntry>?> _fetchContinue() async {
    final resumeFuture = _safe(widget.api.getResumeItems(userId: _userId));
    final nextFuture = _safe(widget.api.getNextUp(userId: _userId));
    final resume = await resumeFuture;
    final next = await nextFuture;
    if (resume == null && next == null) return null;
    final now = DateTime.now();
    final nextEntries = [
      for (final json in next ?? const <Map<String, dynamic>>[])
        ResumeEntry.fromJson(
          json,
          nextLabel: nextUpLabel(
            DateTime.tryParse((json['DateCreated'] as String?) ?? ''),
            now,
          ),
        ),
    ];
    // Où en est chaque série : écarter celles jamais vraiment commencées,
    // et placer les autres selon leur dernière lecture
    final seriesIds = {for (final e in nextEntries) ?e.seriesId}.toList();
    final series = await _safe(
      widget.api.getUserData(userId: _userId, itemIds: seriesIds),
    );
    return mergeContinueWatching(
      resume ?? const [],
      nextEntries,
      series ?? const {},
    );
  }

  /// Met à jour « Continuer à regarder » (au retour du lecteur ou d'une
  /// fiche, ou en revenant sur l'onglet).
  Future<void> refreshContinue() async {
    final entries = await _fetchContinue();
    if (mounted && entries != null) setState(() => _continue = entries);
  }

  // ---------- Actions ----------

  /// Ouvre la fiche d'un film ou d'une série ; au retour, « Continuer à
  /// regarder » est mis à jour.
  Future<void> _open(
    MediaItem item, {
    String? heroTag,
    String? seasonId,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => item.isSeries
            ? SeriesScreen(
                api: widget.api,
                session: widget.session,
                series: item,
                initialSeasonId: seasonId,
                heroTag: heroTag,
              )
            : MovieScreen(
                api: widget.api,
                session: widget.session,
                movie: item,
                heroTag: heroTag,
              ),
      ),
    );
    await refreshContinue();
  }

  /// Lit une entrée de « Continuer à regarder » (à la position [start] si
  /// elle est précisée).
  Future<void> _playEntry(ResumeEntry entry, {Duration? start}) async {
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
    await refreshContinue();
  }

  /// Appui long : reprendre, depuis le début, la fiche, ou retirer.
  Future<void> _showOptions(ResumeEntry entry) async {
    final action = await showResumeActions(context, entry);
    if (!mounted) return;
    switch (action) {
      case ResumeAction.resume:
        await _playEntry(entry);
      case ResumeAction.restart:
        await _playEntry(entry, start: Duration.zero);
      case ResumeAction.openDetails:
        await _open(
          entry.poster,
          heroTag: resumeHeroTag(entry),
          seasonId: entry.seasonId,
        );
      case ResumeAction.remove:
        await _remove(entry);
      case null:
        break;
    }
  }

  /// Efface la progression (comme jamais regardé) : l'affiche disparaît
  /// tout de suite, avec « Annuler » quelques secondes.
  Future<void> _remove(ResumeEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(
      () => _continue = [
        for (final other in _continue)
          if (other.id != entry.id) other,
      ],
    );
    try {
      await widget.api.updateWatchProgress(
        userId: _userId,
        itemId: entry.id,
        position: Duration.zero,
        played: false,
      );
    } on JellyfinException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      await refreshContinue();
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Retiré de Continuer à regarder'),
        // Disparaît tout seul, même avec un bouton
        persist: false,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Annuler',
          textColor: AppColors.white,
          onPressed: () => _undoRemove(entry),
        ),
      ),
    );
  }

  Future<void> _undoRemove(ResumeEntry entry) async {
    try {
      await widget.api.updateWatchProgress(
        userId: _userId,
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
    await refreshContinue();
  }

  /// « Lecture » de « À la une » : le film (là où on s'était arrêté), ou
  /// l'épisode à regarder de la série (sinon sa fiche).
  Future<void> _playHero(HeroItem hero) async {
    if (hero.isSeries) {
      final next = await _safe(
        widget.api.getNextUp(userId: _userId, seriesId: hero.item.id, limit: 1),
      );
      if (!mounted) return;
      if (next == null || next.isEmpty) {
        await _open(hero.item);
        return;
      }
      await _playEntry(ResumeEntry.fromJson(next.first, nextLabel: ''));
      return;
    }
    final progress = hero.details.progress;
    if (_starting) return;
    _starting = true;
    await launchPlayback(
      context,
      api: widget.api,
      session: widget.session,
      itemId: hero.item.id,
      title: hero.item.name,
      start: progress.canResume ? progress.position : Duration.zero,
    );
    _starting = false;
    await refreshContinue();
  }

  void _seeAll(String title, String sortBy, {DateTime? releasedBefore}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SortedItemsScreen(
          api: widget.api,
          session: widget.session,
          title: title,
          itemType: 'Movie',
          sortBy: sortBy,
          releasedBefore: releasedBefore,
        ),
      ),
    );
  }

  void _openDownloads() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DownloadsScreen(api: widget.api, session: widget.session),
      ),
    );
  }

  // ---------- Affichage ----------

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayout.of(context);
    final showHero = !_loading && !_failed && _hero.isNotEmpty;
    // Tablette : « À la une » passe sous l'en-tête transparent
    final top = layout.isWide && showHero ? 0.0 : widget.headerHeight + 4;

    final rows = _loading ? _skeleton(layout) : _rows();
    return RefreshIndicator(
      onRefresh: _load,
      edgeOffset: widget.headerHeight,
      child: ListView(
        controller: widget.controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: top, bottom: widget.bottomPadding + 24),
        children: [
          if (_failed) _OfflineCard(onRetry: _retry),
          if (showHero)
            EntranceAnimation(
              child: HomeHero(
                api: widget.api,
                items: _hero,
                onPlay: _playHero,
                onInfo: (hero) => _open(hero.item),
              ),
            ),
          for (final (i, row) in rows.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 26),
              // Les rangées arrivent l'une après l'autre
              child: _loading
                  ? row
                  : EntranceAnimation(
                      delay: Duration(milliseconds: 80 + 70 * i),
                      child: row,
                    ),
            ),
        ],
      ),
    );
  }

  Future<void> _retry() async {
    await ConnectionMonitor.instance.check();
    await _load();
  }

  List<Widget> _skeleton(HomeLayout layout) => [
    Padding(
      padding: EdgeInsets.symmetric(
        horizontal: layout.isWide ? 0 : layout.gutter,
      ),
      child: SkeletonBox(
        height: layout.isWide ? 470 : 420,
        radius: layout.isWide ? 0 : AppRadius.card,
      ),
    ),
    const MediaRowSkeleton(),
    const MediaRowSkeleton(),
  ];

  /// Les rangées dans l'ordre choisi ; les vides sont laissées de côté.
  List<Widget> _rows() {
    final now = DateTime.now();
    return [
      if (_continue.isNotEmpty)
        ContinueWatchingRow(
          api: widget.api,
          entries: _continue,
          onPlay: _playEntry,
          onOptions: _showOptions,
        ),
      if (_latestMovies.isNotEmpty)
        MediaRow(
          title: 'Films ajoutés récemment',
          onSeeAll: () => _seeAll('Ajoutés récemment', 'DateCreated'),
          children: [
            for (final json in _latestMovies)
              _movieTile(
                MediaItem.fromJson(json),
                'home-added',
                addedLabel(
                  DateTime.tryParse((json['DateCreated'] as String?) ?? ''),
                  now,
                  year: json['ProductionYear'] as int?,
                ),
              ),
          ],
        ),
      if (_newEpisodes.isNotEmpty)
        MediaRow(
          title: 'Nouveaux épisodes',
          children: [
            for (final entry in _newEpisodes)
              MediaTile(
                api: widget.api,
                item: entry.series,
                title: entry.series.name,
                subtitle: entry.label,
                heroTag: 'home-episodes-${entry.series.id}',
                overlays: [
                  if (entry.count > 1)
                    PosterChip('${entry.count} nouveaux', right: true),
                ],
                onTap: () => _open(
                  entry.series,
                  heroTag: 'home-episodes-${entry.series.id}',
                  seasonId: entry.seasonId,
                ),
              ),
          ],
        ),
      if (_released.isNotEmpty)
        MediaRow(
          title: 'Sortis récemment',
          onSeeAll: () => _seeAll(
            'Sortis récemment',
            'PremiereDate',
            releasedBefore: DateTime.now(),
          ),
          children: [
            for (final movie in _released)
              _movieTile(movie, 'home-released', movie.year?.toString() ?? ''),
          ],
        ),
      _DownloadedRow(
        api: widget.api,
        onOpen: (item, heroTag, seasonId) =>
            _open(item, heroTag: heroTag, seasonId: seasonId),
        onSeeAll: _openDownloads,
      ),
    ];
  }

  Widget _movieTile(MediaItem movie, String row, String subtitle) {
    final heroTag = '$row-${movie.id}';
    return MediaTile(
      api: widget.api,
      item: movie,
      title: movie.name,
      subtitle: subtitle,
      heroTag: heroTag,
      onTap: () => _open(movie, heroTag: heroTag),
    );
  }
}

/// Rangée « Téléchargés » : films et séries gardés sur le téléphone (même
/// hors ligne). Rien si aucun téléchargement n'est terminé.
class _DownloadedRow extends StatelessWidget {
  const _DownloadedRow({
    required this.api,
    required this.onOpen,
    required this.onSeeAll,
  });

  final JellyfinApi api;
  final void Function(MediaItem item, String heroTag, String? seasonId) onOpen;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final manager = DownloadManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final groups = DownloadGroups.of(manager.states);
        if (groups.movies.isEmpty && groups.series.isEmpty) {
          return const SizedBox.shrink();
        }
        const check = Positioned(
          top: 6,
          right: 6,
          child: CircleAvatar(
            radius: 11,
            backgroundColor: AppColors.white,
            child: Icon(
              Icons.download_done_rounded,
              size: 14,
              color: AppColors.black,
            ),
          ),
        );
        return MediaRow(
          title: 'Téléchargés',
          onSeeAll: onSeeAll,
          children: [
            for (final entry in groups.movies)
              MediaTile(
                api: api,
                item: entry.info.posterItem,
                title: entry.info.name,
                subtitle: entry.info.year?.toString() ?? '',
                heroTag: 'home-downloaded-${entry.id}',
                overlays: const [check],
                onTap: () => onOpen(
                  entry.info.posterItem,
                  'home-downloaded-${entry.id}',
                  null,
                ),
              ),
            for (final series in groups.series)
              MediaTile(
                api: api,
                item: series.sample.posterItem,
                title: series.name,
                subtitle: seriesSummary(series),
                heroTag: 'home-downloaded-${series.seriesId}',
                overlays: const [check],
                onTap: () => onOpen(
                  series.sample.posterItem,
                  'home-downloaded-${series.seriesId}',
                  series
                      .episodeToOpen(
                        isWatched: (id) =>
                            OfflineProgress.instance.of(id)?.played ?? false,
                      )
                      .seasonId,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Le serveur ne répond pas : message et « Réessayer » (les téléchargements
/// restent juste en dessous).
class _OfflineCard extends StatelessWidget {
  const _OfflineCard({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayout.of(context);
    final textTheme = Theme.of(context).textTheme;
    final connection = ConnectionMonitor.instance;
    return Padding(
      padding: EdgeInsets.fromLTRB(layout.gutter, 12, layout.gutter, 0),
      child: GlassPanel(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_rounded, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connection.online ? 'Serveur injoignable' : 'Hors ligne',
                      style: textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tes téléchargements restent disponibles.',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('Réessayer')),
            ],
          ),
        ),
      ),
    );
  }
}
