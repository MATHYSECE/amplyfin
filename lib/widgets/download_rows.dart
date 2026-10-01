import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/download_info.dart';
import '../models/file_size.dart';
import '../services/connection_monitor.dart';
import '../services/download_groups.dart';
import '../services/download_manager.dart';
import '../services/offline_progress.dart';
import '../theme/app_theme.dart';
import 'download_controls.dart';
import 'poster_image.dart';
import 'ui.dart';

/// Morceaux communs aux écrans « Téléchargements » et « série
/// téléchargée ».

/// Affiche d'un téléchargement : le fichier gardé sur le téléphone, sinon
/// celle du serveur. [hero] : l'affiche glisse vers la fiche.
class DownloadPoster extends StatelessWidget {
  const DownloadPoster({
    super.key,
    required this.api,
    required this.info,
    this.width = 52,
    this.hero = false,
    this.showProgress = false,
  });

  final JellyfinApi api;
  final DownloadInfo info;
  final double width;
  final bool hero;

  /// Fine barre en bas : où en est la lecture.
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final file = DownloadManager.instance.posterFile(info.itemId);
    final network = PosterImage(api: api, item: info.posterItem);
    Widget image = file == null
        ? network
        : Card(
            child: Image.file(
              file,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: 300,
              // Pas encore téléchargée (ou ancien téléchargement) : le serveur
              errorBuilder: (_, _, _) => network,
            ),
          );
    if (hero) {
      image = Hero(
        tag: PosterImage.downloadHeroTag(info.posterItem),
        child: image,
      );
    }
    return SizedBox(
      width: width,
      height: width * 1.5,
      child: showProgress
          ? _WithProgress(itemId: info.itemId, child: image)
          : image,
    );
  }
}

/// Vignette d'un épisode téléchargé (fichier du téléphone, sinon serveur,
/// sinon son numéro).
class DownloadThumbnail extends StatelessWidget {
  const DownloadThumbnail({
    super.key,
    required this.api,
    required this.info,
    this.width = 112,
    this.showProgress = false,
  });

  final JellyfinApi api;
  final DownloadInfo info;
  final double width;

  /// Fine barre en bas : où en est la lecture.
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final placeholder = Center(
      child: Text(
        '${info.episodeNumber ?? ''}',
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(color: AppColors.greyDark),
      ),
    );
    final url = api.imageUrl(
      itemId: info.itemId,
      type: 'Primary',
      tag: info.imageTag,
      width: 480,
    );
    final network = url == null
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            memCacheWidth: 480,
            placeholder: (_, _) => const SizedBox.shrink(),
            errorWidget: (_, _, _) => placeholder,
          );
    final file = DownloadManager.instance.thumbFile(info.itemId);
    final image = Card(
      child: file == null
          ? network
          : Image.file(
              file,
              fit: BoxFit.cover,
              cacheWidth: 480,
              errorBuilder: (_, _, _) => network,
            ),
    );
    return SizedBox(
      width: width,
      height: width * 9 / 16,
      child: showProgress
          ? _WithProgress(itemId: info.itemId, child: image)
          : image,
    );
  }
}

/// Image avec, en bas, la part déjà vue (position gardée sur le téléphone),
/// ou une coche si c'est déjà vu.
class _WithProgress extends StatelessWidget {
  const _WithProgress({required this.itemId, required this.child});

  final String itemId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final saved = OfflineProgress.instance.of(itemId);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (saved != null && saved.played)
          const Positioned(
            top: 4,
            right: 4,
            child: CircleAvatar(
              radius: 9,
              backgroundColor: AppColors.white,
              child: Icon(
                Icons.check_rounded,
                size: 12,
                color: AppColors.black,
              ),
            ),
          )
        else if (saved != null && saved.fraction > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(AppRadius.poster),
              ),
              child: ProgressLine(value: saved.fraction),
            ),
          ),
      ],
    );
  }
}

/// Titre de section (« En cours », « Films »…) avec un petit texte à droite.
class DownloadSectionTitle extends StatelessWidget {
  const DownloadSectionTitle({
    super.key,
    required this.title,
    this.detail,
    this.action,
  });

  final String title;
  final String? detail;

  /// Bouton à droite (ex. « Supprimer » une saison).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(title, style: textTheme.titleMedium)),
          if (detail != null)
            Text(
              detail!,
              style: textTheme.labelMedium?.copyWith(color: AppColors.grey),
            ),
          ?action,
        ],
      ),
    );
  }
}

/// Barre fine d'avancée d'un téléchargement : se remplit doucement, grisée
/// en pause, animée sans valeur en attente.
class DownloadProgressBar extends StatelessWidget {
  const DownloadProgressBar({super.key, required this.state});

  final DownloadState state;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(4));
    if (state.phase == DownloadPhase.waiting) {
      return const LinearProgressIndicator(
        minHeight: 4,
        borderRadius: radius,
        backgroundColor: AppColors.track,
        color: AppColors.trackBuffer,
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: state.progress),
      duration: AppDurations.medium,
      builder: (context, value, _) => LinearProgressIndicator(
        value: value,
        minHeight: 4,
        borderRadius: radius,
        backgroundColor: AppColors.track,
        color: state.phase == DownloadPhase.paused
            ? AppColors.trackBuffer
            : AppColors.white,
      ),
    );
  }
}

/// « 5 épisodes · 3,1 Go · 2 en cours ».
String seriesSummary(SeriesDownloads series) {
  final count = series.complete.length;
  return joinInfos([
    '$count épisode${count > 1 ? 's' : ''}',
    ?formatFileSize(series.completeBytes),
    if (series.pendingCount > 0) '${series.pendingCount} en cours',
  ]);
}

/// Texte d'avancée : « 3,1 Go / 18,7 Go · 17 % », « En pause · 17 % »…
String pendingLabel(DownloadState state) {
  final percent = (state.progress * 100).floor();
  switch (state.phase) {
    case DownloadPhase.waiting:
      return 'En attente…';
    case DownloadPhase.paused:
      return 'En pause · $percent %';
    case DownloadPhase.failed:
      return state.error ?? 'Le téléchargement a échoué.';
    default:
      final received = formatFileSize(state.receivedBytes);
      final total = formatFileSize(state.size);
      return [
        if (received != null && total != null) '$received / $total',
        '$percent %',
      ].join(' · ');
  }
}

/// Ligne d'un téléchargement pas encore terminé : image, titre, avancée,
/// pause / reprise (l'icône tourne en changeant), et annulation.
/// En échec : « Réessayer » à la place de la pause.
class PendingDownloadRow extends StatelessWidget {
  const PendingDownloadRow({
    super.key,
    required this.api,
    required this.entry,
    required this.onRetry,
    this.episodeStyle = false,
  });

  final JellyfinApi api;
  final DownloadEntry entry;

  /// « Réessayer » après un échec (null : bouton masqué, ex. hors ligne).
  final VoidCallback? onRetry;

  /// Vignette d'épisode et « 6. Titre » (écran d'une série), au lieu de
  /// l'affiche et du nom de la série.
  final bool episodeStyle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final state = entry.state;
    final info = entry.info;
    final manager = DownloadManager.instance;
    final failed = state.phase == DownloadPhase.failed;
    final paused = state.phase == DownloadPhase.paused;
    final title = episodeStyle
        ? info.episodeTitle
        : (info.isEpisode ? (info.seriesName ?? info.name) : info.name);
    final code = !episodeStyle ? info.episodeCode : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (episodeStyle)
            DownloadThumbnail(api: api, info: info)
          else
            DownloadPoster(api: api, info: info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  [?code, pendingLabel(state)].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: failed ? AppColors.error : AppColors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!failed) ...[
                  const SizedBox(height: 8),
                  DownloadProgressBar(state: state),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (failed)
            if (onRetry != null)
              GlassCircleButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Réessayer',
                size: 40,
                onPressed: onRetry,
              )
            else
              const SizedBox.shrink()
          else
            // En attente : pas de pause possible, le bouton s'efface
            AnimatedScale(
              scale: state.phase == DownloadPhase.waiting ? 0.6 : 1,
              duration: AppDurations.fast,
              child: AnimatedOpacity(
                opacity: state.phase == DownloadPhase.waiting ? 0 : 1,
                duration: AppDurations.fast,
                child: IgnorePointer(
                  ignoring: state.phase == DownloadPhase.waiting,
                  child: GlassCircleButton(
                    tooltip: paused ? 'Reprendre' : 'Mettre en pause',
                    size: 40,
                    onPressed: () => paused
                        ? manager.resume(entry.id)
                        : manager.pause(entry.id),
                    child: AnimatedSwitcher(
                      duration: AppDurations.medium,
                      switchInCurve: Curves.easeOutBack,
                      transitionBuilder: (child, animation) =>
                          RotationTransition(
                            turns: Tween(
                              begin: -0.25,
                              end: 0.0,
                            ).animate(animation),
                            child: ScaleTransition(
                              scale: animation,
                              child: child,
                            ),
                          ),
                      child: Icon(
                        paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        key: ValueKey(paused),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          GlassCircleButton(
            icon: Icons.close_rounded,
            tooltip: 'Annuler le téléchargement',
            size: 40,
            onPressed: () => confirmCancelDownload(context, entry.id),
          ),
        ],
      ),
    );
  }
}

/// Ligne qu'on glisse vers la gauche pour la supprimer : le fond
/// « Supprimer » apparaît, puis devient blanc quand on a glissé assez loin.
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({
    super.key,
    required this.itemId,
    required this.onDelete,
    required this.child,
  });

  final String itemId;
  final VoidCallback onDelete;
  final Widget child;

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> {
  /// Vrai quand on a glissé assez loin pour supprimer en lâchant.
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    final foreground = _armed ? AppColors.black : AppColors.white;
    return Dismissible(
      key: ValueKey('swipe-${widget.itemId}'),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.35},
      // Pas de rétrécissement ici : les lignes du dessous remontent en
      // glissant (MoveAnimated)
      resizeDuration: null,
      onUpdate: (details) {
        if (details.reached != _armed) setState(() => _armed = details.reached);
      },
      onDismissed: (_) => widget.onDelete(),
      background: AnimatedContainer(
        duration: AppDurations.fast,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: _armed ? AppColors.white : AppColors.surface3,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _armed ? 1.2 : 1,
              duration: AppDurations.fast,
              curve: Curves.easeOutBack,
              child: Icon(Icons.delete_outline_rounded, color: foreground),
            ),
            const SizedBox(width: 8),
            Text(
              'Supprimer',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
      child: widget.child,
    );
  }
}

/// Choix du menu ⋯ (ou de l'appui long) sur un téléchargement terminé.
enum DownloadAction { play, details, delete }

/// Panneau qui monte du bas : Lire, Voir la fiche, Supprimer.
Future<DownloadAction?> showDownloadActions(
  BuildContext context, {
  required JellyfinApi api,
  required DownloadInfo info,
  bool showDetails = true,
}) {
  final textTheme = Theme.of(context).textTheme;
  return showModalBottomSheet<DownloadAction>(
    context: context,
    builder: (context) {
      Widget option(DownloadAction action, IconData icon, String label) =>
          ListTile(
            leading: Icon(icon),
            title: Text(label, style: textTheme.titleSmall),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onTap: () => Navigator.of(context).pop(action),
          );
      final size = formatFileSize(info.size);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
                child: Row(
                  children: [
                    if (info.isEpisode)
                      DownloadThumbnail(api: api, info: info, width: 96)
                    else
                      DownloadPoster(api: api, info: info, width: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.isEpisode ? info.episodeTitle : info.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            joinInfos([
                              if (info.isEpisode) ?info.seriesName,
                              ?info.episodeCode,
                              if (size != null) 'Téléchargé · $size',
                            ]),
                            style: textTheme.bodySmall?.copyWith(
                              color: AppColors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              const SizedBox(height: 6),
              option(DownloadAction.play, Icons.play_arrow_rounded, 'Lire'),
              if (showDetails)
                option(
                  DownloadAction.details,
                  Icons.info_outline_rounded,
                  info.isEpisode
                      ? 'Voir la fiche de la série'
                      : 'Voir la fiche',
                ),
              option(
                DownloadAction.delete,
                Icons.delete_outline_rounded,
                'Supprimer le téléchargement',
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Suppression avec « Annuler » : les lignes disparaissent tout de suite,
/// et les fichiers ne sont vraiment effacés que si on n'annule pas.
mixin UndoDelete<T extends StatefulWidget> on State<T> {
  /// Téléchargements cachés en attendant la fin du message.
  final Set<String> hiddenDownloads = {};

  void deleteWithUndo(List<String> itemIds, String message) {
    if (itemIds.isEmpty) return;
    setState(() => hiddenDownloads.addAll(itemIds));
    final messenger = ScaffoldMessenger.of(context);
    // Un message précédent se ferme : sa suppression est confirmée
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        // Disparaît tout seul, même avec un bouton
        persist: false,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Annuler',
          textColor: AppColors.white,
          onPressed: () {},
        ),
      ),
    );
    controller.closed.then((reason) async {
      if (reason != SnackBarClosedReason.action) {
        await DownloadManager.instance.removeAll(itemIds);
      }
      if (mounted) setState(() => hiddenDownloads.removeAll(itemIds));
    });
  }
}

/// Bandeau de connexion en haut des téléchargements : « Hors ligne » (avec
/// « Réessayer »), puis « Connexion retrouvée » si [onOpenLibrary] est
/// donné (démarrage hors ligne). Rien quand tout va bien.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, this.onOpenLibrary});

  final VoidCallback? onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final connection = ConnectionMonitor.instance;
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final Widget banner;
        if (!connection.online) {
          banner = _banner(
            context,
            key: 'offline',
            icon: Icons.cloud_off_rounded,
            title: 'Hors ligne',
            message: 'Tes téléchargements restent disponibles.',
            action: connection.checking
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : TextButton(
                    onPressed: connection.check,
                    child: const Text('Réessayer'),
                  ),
          );
        } else if (connection.recovered && onOpenLibrary != null) {
          banner = _banner(
            context,
            key: 'recovered',
            icon: Icons.cloud_done_outlined,
            title: 'Connexion retrouvée',
            message: 'Le serveur répond de nouveau.',
            action: TextButton(
              onPressed: onOpenLibrary,
              child: const Text('Ouvrir la bibliothèque'),
            ),
          );
        } else {
          banner = const SizedBox(
            key: ValueKey('none'),
            width: double.infinity,
          );
        }
        return AnimatedSize(
          duration: AppDurations.medium,
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(duration: AppDurations.medium, child: banner),
        );
      },
    );
  }

  Widget _banner(
    BuildContext context, {
    required String key,
    required IconData icon,
    required String title,
    required String message,
    required Widget action,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      key: ValueKey(key),
      padding: const EdgeInsets.only(top: 16),
      child: GlassPanel(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
          child: Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              action,
            ],
          ),
        ),
      ),
    );
  }
}
