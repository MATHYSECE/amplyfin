import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/download_info.dart';
import '../models/file_size.dart';
import '../models/session.dart';
import '../services/device_storage.dart';
import '../services/download_groups.dart';
import '../services/download_manager.dart';
import '../services/playback_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/download_rows.dart';
import '../widgets/poster_image.dart';
import '../widgets/transitions.dart';
import '../widgets/ui.dart';
import 'downloaded_series_screen.dart';
import 'movie_screen.dart';
import 'series_screen.dart';

/// Écran « Téléchargements » : place sur le téléphone, téléchargements en
/// cours (pause, reprise, annulation), films, et séries (un appui ouvre
/// leurs épisodes). Un film téléchargé se lit d'un appui ; ⋯ ou un appui
/// long ouvre le menu ; glisser vers la gauche supprime (avec « Annuler »).
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.api, required this.session});

  final JellyfinApi api;
  final Session session;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> with UndoDelete {
  final _manager = DownloadManager.instance;

  /// Place libre et totale du téléphone (null tant qu'inconnue).
  DeviceSpace? _space;
  Timer? _spaceTimer;

  @override
  void initState() {
    super.initState();
    _readSpace();
    // La place libre change pendant les téléchargements
    _spaceTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _readSpace(),
    );
  }

  @override
  void dispose() {
    _spaceTimer?.cancel();
    super.dispose();
  }

  Future<void> _readSpace() async {
    final space = await DeviceStorage.read();
    if (mounted && space != null) setState(() => _space = space);
  }

  void _retry(DownloadEntry entry) => _manager.start(
    api: widget.api,
    userId: widget.session.userId,
    itemId: entry.id,
  );

  Future<void> _play(DownloadInfo info) => launchDownloadPlayback(
    context,
    api: widget.api,
    session: widget.session,
    info: info,
  );

  /// Fiche du film, ou de la série ouverte sur la saison de l'épisode.
  void _openDetails(DownloadInfo info) {
    final heroTag = PosterImage.downloadHeroTag(info.posterItem);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => info.isEpisode
            ? SeriesScreen(
                api: widget.api,
                session: widget.session,
                series: info.posterItem,
                initialSeasonId: info.seasonId,
                heroTag: heroTag,
              )
            : MovieScreen(
                api: widget.api,
                session: widget.session,
                movie: info.posterItem,
                heroTag: heroTag,
              ),
      ),
    );
  }

  Future<void> _showActions(DownloadEntry entry) async {
    final action = await showDownloadActions(
      context,
      api: widget.api,
      info: entry.info,
    );
    if (!mounted) return;
    switch (action) {
      case DownloadAction.play:
        await _play(entry.info);
      case DownloadAction.details:
        _openDetails(entry.info);
      case DownloadAction.delete:
        _delete(entry);
      case null:
        break;
    }
  }

  void _delete(DownloadEntry entry) =>
      deleteWithUndo([entry.id], '« ${entry.info.name} » supprimé');

  void _openSeries(SeriesDownloads series) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DownloadedSeriesScreen(
          api: widget.api,
          session: widget.session,
          seriesId: series.seriesId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      body: GlowBackground(
        child: EdgeSwipeBack(
          child: ListenableBuilder(
            listenable: _manager,
            builder: (context, _) {
              final groups = DownloadGroups.of(
                _manager.states,
                hidden: hiddenDownloads,
              );
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  padding.top + 12,
                  20,
                  padding.bottom + 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        GlassCircleButton(
                          icon: Icons.chevron_left_rounded,
                          tooltip: 'Retour',
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Téléchargements',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Les blocs arrivent l'un après l'autre à l'ouverture
                    EntranceAnimation(
                      delay: const Duration(milliseconds: 160),
                      child: _StorageCard(
                        used: _manager.usedBytes,
                        space: _space,
                      ),
                    ),
                    EntranceAnimation(
                      delay: const Duration(milliseconds: 240),
                      child: AnimatedSwitcher(
                        duration: AppDurations.medium,
                        child: groups.isEmpty
                            ? const _EmptyDownloads()
                            : MoveScope(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: _buildList(groups),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Toutes les lignes à plat (titres compris) : chacune garde sa clé, et
  /// glisse vers sa nouvelle place quand la liste change.
  List<Widget> _buildList(DownloadGroups groups) {
    Widget item(Key key, Widget child) => MoveAnimated(key: key, child: child);
    return [
      if (groups.pending.isNotEmpty) ...[
        item(
          const ValueKey('title-pending'),
          DownloadSectionTitle(
            title: 'En cours',
            detail: '${groups.pending.length}',
          ),
        ),
        for (final entry in groups.pending)
          item(
            ValueKey(entry.id),
            PendingDownloadRow(
              api: widget.api,
              entry: entry,
              onRetry: () => _retry(entry),
            ),
          ),
      ],
      if (groups.movies.isNotEmpty) ...[
        item(
          const ValueKey('title-movies'),
          DownloadSectionTitle(
            title: 'Films',
            detail: '${groups.movies.length}',
          ),
        ),
        for (final entry in groups.movies)
          item(
            ValueKey(entry.id),
            SwipeToDelete(
              itemId: entry.id,
              onDelete: () => _delete(entry),
              child: _MovieRow(
                api: widget.api,
                entry: entry,
                onPlay: () => _play(entry.info),
                onActions: () => _showActions(entry),
              ),
            ),
          ),
      ],
      if (groups.series.isNotEmpty) ...[
        item(
          const ValueKey('title-series'),
          DownloadSectionTitle(
            title: 'Séries',
            detail: '${groups.series.length}',
          ),
        ),
        for (final series in groups.series)
          item(
            ValueKey('series-${series.seriesId}'),
            _SeriesRow(
              api: widget.api,
              series: series,
              onTap: () => _openSeries(series),
            ),
          ),
      ],
    ];
  }
}

/// Place sur le téléphone : Amplyfin, les autres applis, et le libre.
class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.used, required this.space});

  final int used;
  final DeviceSpace? space;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(
      color: AppColors.grey,
      fontWeight: FontWeight.w600,
    );
    final space = this.space;
    final usedLabel = formatFileSize(used) ?? '0 Go';
    final freeLabel = formatFileSize(space?.free);
    final other = space == null
        ? 0
        : (space.total - space.free - used).clamp(0, space.total);

    Widget dot(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: muted),
      ],
    );

    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(usedLabel, style: textTheme.titleMedium),
                Text(' pour Amplyfin', style: muted),
                const Spacer(),
                if (freeLabel != null) Text('$freeLabel libres', style: muted),
              ],
            ),
            if (space != null) ...[
              const SizedBox(height: 12),
              // Barre : Amplyfin (blanc), autres applis (gris), libre
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 8,
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: used / space.total),
                          duration: AppDurations.emphasized,
                          curve: Curves.easeInOutCubicEmphasized,
                          builder: (context, app, _) {
                            final width = constraints.maxWidth;
                            return Row(
                              children: [
                                _BarPart(
                                  width: width * app.clamp(0.0, 1.0),
                                  color: AppColors.white,
                                ),
                                const SizedBox(width: 2),
                                // Jamais plus que la place restante
                                _BarPart(
                                  width: math.min(
                                    width * other / space.total,
                                    width * (1 - app) - 2,
                                  ),
                                  color: AppColors.trackBuffer,
                                ),
                                const Expanded(
                                  child: ColoredBox(
                                    color: AppColors.glassStrong,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  dot(AppColors.white, 'Amplyfin'),
                  dot(AppColors.trackBuffer, 'Autres applis'),
                  dot(AppColors.glassStrong, 'Libre'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Morceau de la barre de place, [width] pixels de large.
class _BarPart extends StatelessWidget {
  const _BarPart({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width.clamp(0.0, double.infinity),
      child: ColoredBox(color: color),
    );
  }
}

/// Ligne d'un film téléchargé : affiche, titre, année · durée · taille, ⋯.
class _MovieRow extends StatelessWidget {
  const _MovieRow({
    required this.api,
    required this.entry,
    required this.onPlay,
    required this.onActions,
  });

  final JellyfinApi api;
  final DownloadEntry entry;
  final VoidCallback onPlay;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final info = entry.info;
    return InkWell(
      onTap: onPlay,
      onLongPress: onActions,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            DownloadPoster(api: api, info: info, hero: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    joinInfos([
                      if (info.year != null) '${info.year}',
                      ?info.runtimeLabel,
                      ?formatFileSize(entry.state.size),
                    ]),
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            GlassCircleButton(
              icon: Icons.more_horiz_rounded,
              tooltip: 'Plus d\'options',
              size: 40,
              onPressed: onActions,
            ),
          ],
        ),
      ),
    );
  }
}

/// Ligne d'une série : affiche, nom, nombre d'épisodes et place prise.
class _SeriesRow extends StatelessWidget {
  const _SeriesRow({
    required this.api,
    required this.series,
    required this.onTap,
  });

  final JellyfinApi api;
  final SeriesDownloads series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            DownloadPoster(api: api, info: series.sample, hero: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    series.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    seriesSummary(series),
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.greyDark),
          ],
        ),
      ),
    );
  }
}

/// Rien de téléchargé : où trouver le bouton.
class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AppColors.glass,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: const Icon(Icons.download_rounded, size: 32),
          ),
          const SizedBox(height: 16),
          Text('Aucun téléchargement', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Sur la fiche d\'un film ou d\'un épisode, touche « Télécharger » '
            'pour le regarder sans connexion.',
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(color: AppColors.textSoft),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Parcourir la bibliothèque'),
          ),
        ],
      ),
    );
  }
}
