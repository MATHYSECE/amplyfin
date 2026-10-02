import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/download_info.dart';
import '../models/file_size.dart';
import '../models/session.dart';
import '../services/connection_monitor.dart';
import '../services/download_groups.dart';
import '../services/download_manager.dart';
import '../services/offline_progress.dart';
import '../services/playback_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/download_rows.dart';
import '../widgets/poster_image.dart';
import '../widgets/transitions.dart';
import '../widgets/ui.dart';
import 'series_screen.dart';

/// Les épisodes téléchargés d'une série, rangés par saison : lecture d'un
/// appui, menu ⋯ ou appui long, glisser pour supprimer, suppression d'une
/// saison entière.
class DownloadedSeriesScreen extends StatefulWidget {
  const DownloadedSeriesScreen({
    super.key,
    required this.api,
    required this.session,
    required this.seriesId,
  });

  final JellyfinApi api;
  final Session session;
  final String seriesId;

  @override
  State<DownloadedSeriesScreen> createState() => _DownloadedSeriesScreenState();
}

class _DownloadedSeriesScreenState extends State<DownloadedSeriesScreen>
    with UndoDelete {
  final _manager = DownloadManager.instance;
  final _connection = ConnectionMonitor.instance;

  /// Dernière version connue de la série (gardée pour le titre pendant
  /// qu'on revient en arrière, une fois tout supprimé).
  SeriesDownloads? _last;
  bool _leaving = false;

  Future<void> _play(DownloadInfo info) => launchDownloadPlayback(
    context,
    api: widget.api,
    session: widget.session,
    info: info,
  );

  void _openSeries(DownloadInfo info, {String? seasonId}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeriesScreen(
          api: widget.api,
          session: widget.session,
          series: info.posterItem,
          initialSeasonId: seasonId,
          heroTag: PosterImage.downloadHeroTag(info.posterItem),
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
        _openSeries(entry.info, seasonId: entry.info.seasonId);
      case DownloadAction.delete:
        _delete(entry);
      case null:
        break;
    }
  }

  void _delete(DownloadEntry entry) => deleteWithUndo(
    [entry.id],
    'Épisode ${entry.info.episodeNumber ?? ''} '
    'supprimé',
  );

  Future<void> _deleteSeason(int? season, List<DownloadEntry> episodes) async {
    final done = [
      for (final e in episodes)
        if (e.isComplete) e.id,
    ];
    final name = season == null ? 'ces épisodes' : 'la saison $season';
    if (await showConfirmDialog(
      context,
      title: 'Supprimer $name ?',
      message:
          '${done.length} épisode${done.length > 1 ? 's' : ''} '
          'téléchargé${done.length > 1 ? 's' : ''} seront effacés du '
          'téléphone. Ils restent disponibles sur le serveur.',
      action: 'Supprimer',
    )) {
      deleteWithUndo(
        done,
        season == null ? 'Épisodes supprimés' : 'Saison $season supprimée',
      );
    }
  }

  /// Plus rien à montrer : retour à l'écran des téléchargements.
  void _leave() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: GlowBackground(
        // Tout l'écran, même si la liste est courte
        child: SizedBox.expand(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              _manager,
              _connection,
              OfflineProgress.instance,
            ]),
            builder: (context, _) {
              final series = DownloadGroups.of(
                _manager.states,
                hidden: hiddenDownloads,
              ).allSeries[widget.seriesId];
              if (series == null) {
                // Tout est supprimé (et « Annuler » n'est plus possible)
                if (hiddenDownloads.isEmpty) _leave();
              } else {
                _last = series;
              }
              final shown = series ?? _last;
              // Tablette : une colonne centrée plutôt que toute la largeur
              final side = AppLayout.isWide(context)
                  ? AppLayout.centeredGutter(context)
                  : 20.0;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  side,
                  padding.top + 12,
                  side,
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
                            shown?.name ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.headlineSmall,
                          ),
                        ),
                      ],
                    ),
                    if (shown != null) ...[
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          DownloadPoster(
                            api: widget.api,
                            info: shown.sample,
                            width: 72,
                            hero: true,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: EntranceAnimation(
                              delay: const Duration(milliseconds: 120),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    series == null ? '' : seriesSummary(series),
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: AppColors.textSoft,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: () => _openSeries(shown.sample),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 38),
                                    ),
                                    icon: const Icon(
                                      Icons.info_outline_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Voir la fiche'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      EntranceAnimation(
                        delay: const Duration(milliseconds: 200),
                        child: MoveScope(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: series == null ? [] : _buildList(series),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Une section par saison : titre (nombre, taille, « Supprimer »), puis
  /// ses épisodes, terminés ou en cours.
  List<Widget> _buildList(SeriesDownloads series) {
    return [
      for (final MapEntry(key: season, value: episodes)
          in series.bySeason.entries) ...[
        MoveAnimated(
          key: ValueKey('season-$season'),
          child: _seasonTitle(season, episodes),
        ),
        for (final entry in episodes)
          MoveAnimated(
            key: ValueKey(entry.id),
            child: entry.isComplete
                ? SwipeToDelete(
                    itemId: entry.id,
                    onDelete: () => _delete(entry),
                    child: _EpisodeRow(
                      api: widget.api,
                      entry: entry,
                      onPlay: () => _play(entry.info),
                      onActions: () => _showActions(entry),
                    ),
                  )
                : PendingDownloadRow(
                    api: widget.api,
                    entry: entry,
                    episodeStyle: true,
                    // Hors ligne : rien à réessayer pour l'instant
                    onRetry: _connection.online
                        ? () => _manager.start(
                            api: widget.api,
                            userId: widget.session.userId,
                            itemId: entry.id,
                          )
                        : null,
                  ),
          ),
      ],
    ];
  }

  Widget _seasonTitle(int? season, List<DownloadEntry> episodes) {
    final done = episodes.where((e) => e.isComplete).toList();
    final size = formatFileSize(
      done.fold<int>(0, (sum, e) => sum + (e.state.size ?? 0)),
    );
    return DownloadSectionTitle(
      title: season == null ? 'Épisodes' : 'Saison $season',
      detail: joinInfos([
        '${done.length} épisode${done.length > 1 ? 's' : ''}',
        ?size,
      ]),
      action: done.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 4),
              child: TextButton(
                onPressed: () => _deleteSeason(season, episodes),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Supprimer'),
              ),
            ),
    );
  }
}

/// Ligne d'un épisode téléchargé : vignette, « 1. Titre », durée · taille, ⋯.
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
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
            DownloadThumbnail(api: api, info: info, showProgress: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.episodeTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    joinInfos([
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
