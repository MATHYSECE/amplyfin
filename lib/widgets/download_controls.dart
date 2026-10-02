import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/episode.dart';
import '../models/file_size.dart';
import '../services/download_groups.dart';
import '../services/download_manager.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Texte d'état d'un téléchargement, pour la ligne d'infos d'un épisode
/// (null : pas téléchargé, on garde les infos habituelles).
String? downloadStatusLabel(DownloadState state) => switch (state.phase) {
  DownloadPhase.none => null,
  DownloadPhase.waiting => 'En attente du téléchargement…',
  DownloadPhase.running =>
    'Téléchargement · ${(state.progress * 100).floor()} %',
  DownloadPhase.paused => 'En pause · ${(state.progress * 100).floor()} %',
  DownloadPhase.complete => [
    'Téléchargé',
    ?formatFileSize(state.size),
  ].join(' · '),
  DownloadPhase.failed => state.error ?? 'Le téléchargement a échoué.',
};

/// Annule un téléchargement en cours (après confirmation).
Future<void> confirmCancelDownload(BuildContext context, String itemId) async {
  if (await showConfirmDialog(
    context,
    title: 'Annuler le téléchargement ?',
    message: 'La partie déjà téléchargée sera effacée du téléphone.',
    action: 'Annuler le téléchargement',
  )) {
    await DownloadManager.instance.remove(itemId);
  }
}

/// Supprime un téléchargement terminé (après confirmation).
Future<void> confirmDeleteDownload(BuildContext context, String itemId) async {
  if (await showConfirmDialog(
    context,
    title: 'Supprimer le téléchargement ?',
    message:
        'Le fichier sera effacé du téléphone. Il reste disponible sur '
        'le serveur.',
    action: 'Supprimer',
  )) {
    await DownloadManager.instance.remove(itemId);
  }
}

/// Fondu enchaîné entre deux états d'un bouton (avec un léger zoom).
Widget _crossFade(Widget child, Animation<double> animation) => FadeTransition(
  opacity: animation,
  child: ScaleTransition(
    scale: Tween(begin: 0.96, end: 1.0).animate(animation),
    child: child,
  ),
);

/// Bouton de téléchargement d'un film, selon l'état : « Télécharger ·
/// 12,4 Go », progression avec annulation, « Téléchargé » avec corbeille,
/// ou « Réessayer » en cas d'échec. [compact] : juste « Télécharger »
/// (à côté de « Depuis le début »), quand rien n'est encore téléchargé.
class MovieDownloadButton extends StatelessWidget {
  const MovieDownloadButton({
    super.key,
    required this.api,
    required this.userId,
    required this.itemId,
    this.fileSize,
    this.compact = false,
  });

  final JellyfinApi api;
  final String userId;
  final String itemId;

  /// Taille du fichier sur le serveur, en octets (si connue).
  final int? fileSize;
  final bool compact;

  void _start() =>
      DownloadManager.instance.start(api: api, userId: userId, itemId: itemId);

  @override
  Widget build(BuildContext context) {
    final manager = DownloadManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final state = manager.stateOf(itemId);
        return AnimatedSwitcher(
          duration: AppDurations.medium,
          transitionBuilder: _crossFade,
          child: KeyedSubtree(
            // Un fondu seulement quand l'état change vraiment (pas à
            // chaque pour cent de progression)
            key: ValueKey(state.isActive ? 'active' : state.phase.name),
            child: _build(context, state),
          ),
        );
      },
    );
  }

  Widget _build(BuildContext context, DownloadState state) {
    final textTheme = Theme.of(context).textTheme;
    switch (state.phase) {
      case DownloadPhase.none:
        final size = formatFileSize(fileSize);
        // Toute la largeur disponible (à côté du bouton « Vu »)
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.download_rounded, size: 22),
            label: Text(
              compact || size == null ? 'Télécharger' : 'Télécharger · $size',
            ),
          ),
        );
      case DownloadPhase.waiting:
      case DownloadPhase.running:
      case DownloadPhase.paused:
        final percent = (state.progress * 100).floor();
        final received = formatFileSize(state.receivedBytes);
        final total = formatFileSize(state.size);
        return Row(
          children: [
            Expanded(
              child: ProgressPill(
                progress: state.progress,
                label: switch (state.phase) {
                  DownloadPhase.waiting => 'En attente…',
                  DownloadPhase.paused => 'En pause · $percent %',
                  _ => 'Téléchargement · $percent %',
                },
                detail: (received != null && total != null)
                    ? '$received / $total'
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            GlassCircleButton(
              icon: Icons.close_rounded,
              tooltip: 'Annuler le téléchargement',
              size: 48,
              onPressed: () => confirmCancelDownload(context, itemId),
            ),
          ],
        );
      case DownloadPhase.complete:
        final size = formatFileSize(state.size);
        return Row(
          children: [
            Expanded(
              child: DonePill(
                label: size == null ? 'Téléchargé' : 'Téléchargé · $size',
              ),
            ),
            const SizedBox(width: 10),
            GlassCircleButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Supprimer le téléchargement',
              size: 48,
              onPressed: () => confirmDeleteDownload(context, itemId),
            ),
          ],
        );
      case DownloadPhase.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.refresh_rounded, size: 22),
              label: const Text('Réessayer le téléchargement'),
            ),
            const SizedBox(height: 8),
            Text(
              state.error ?? 'Le téléchargement a échoué.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ],
        );
    }
  }
}

/// Pilule qui se remplit de gauche à droite pendant le téléchargement.
class ProgressPill extends StatelessWidget {
  const ProgressPill({
    super.key,
    required this.progress,
    required this.label,
    this.detail,
  });

  final double progress;
  final String label;

  /// Petit texte à droite (« 5,2 / 12,4 Go »).
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            // Remplissage qui glisse doucement d'une valeur à l'autre
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress.clamp(0.0, 1.0)),
              duration: AppDurations.medium,
              builder: (context, value, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value,
                child: const ColoredBox(color: AppColors.glassStrong),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelLarge,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pilule pleine « ✓ Téléchargé · 12,4 Go ».
class DonePill extends StatelessWidget {
  const DonePill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.glassStrong,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}

/// Petite mention sous le bouton d'un film téléchargé : la fiche reste
/// consultable sans connexion.
class OfflineNote extends StatelessWidget {
  const OfflineNote({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    final manager = DownloadManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final done = manager.stateOf(itemId).phase == DownloadPhase.complete;
        return AnimatedSize(
          duration: AppDurations.medium,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedOpacity(
            opacity: done ? 1 : 0,
            duration: AppDurations.medium,
            child: !done
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.offline_pin_outlined,
                          size: 16,
                          color: AppColors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Fiche, affiche et sous-titres gardés sur le '
                            'téléphone',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppColors.grey,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// Rond de téléchargement d'un épisode (à côté du bouton ⓘ) :
/// ⬇ à télécharger, cercle qui se remplit pendant le téléchargement (un
/// appui l'annule), rond blanc ✓ une fois téléchargé (un appui propose de
/// supprimer), ou ↻ pour réessayer après un échec. Passe d'un état à
/// l'autre avec un petit rebond.
class EpisodeDownloadButton extends StatelessWidget {
  const EpisodeDownloadButton({
    super.key,
    required this.api,
    required this.userId,
    required this.itemId,
  });

  static const _size = 40.0;

  final JellyfinApi api;
  final String userId;
  final String itemId;

  void _start() =>
      DownloadManager.instance.start(api: api, userId: userId, itemId: itemId);

  @override
  Widget build(BuildContext context) {
    final manager = DownloadManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final state = manager.stateOf(itemId);
        return SizedBox.square(
          dimension: _size,
          child: AnimatedSwitcher(
            duration: AppDurations.medium,
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: KeyedSubtree(
              key: ValueKey(state.isActive ? 'active' : state.phase.name),
              child: _build(context, state),
            ),
          ),
        );
      },
    );
  }

  Widget _build(BuildContext context, DownloadState state) {
    switch (state.phase) {
      case DownloadPhase.none:
        return GlassCircleButton(
          icon: Icons.download_rounded,
          tooltip: 'Télécharger l\'épisode',
          size: _size,
          onPressed: _start,
        );
      case DownloadPhase.waiting:
      case DownloadPhase.running:
      case DownloadPhase.paused:
        return Tooltip(
          message: 'Annuler le téléchargement',
          child: InkResponse(
            onTap: () => confirmCancelDownload(context, itemId),
            radius: _size / 2,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.square(
                  dimension: _size - 4,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: state.progress),
                    duration: AppDurations.medium,
                    builder: (context, value, _) => CircularProgressIndicator(
                      // En attente : cercle qui tourne sans progression
                      value: state.phase == DownloadPhase.waiting
                          ? null
                          : value,
                      strokeWidth: 2.5,
                      backgroundColor: AppColors.track,
                    ),
                  ),
                ),
                const Icon(
                  Icons.stop_rounded,
                  size: 16,
                  color: AppColors.white,
                ),
              ],
            ),
          ),
        );
      case DownloadPhase.complete:
        return Tooltip(
          message: 'Téléchargé',
          child: Material(
            color: AppColors.white,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => confirmDeleteDownload(context, itemId),
              child: const SizedBox.square(
                dimension: _size,
                child: Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: AppColors.black,
                ),
              ),
            ),
          ),
        );
      case DownloadPhase.failed:
        return GlassCircleButton(
          icon: Icons.refresh_rounded,
          tooltip: state.error ?? 'Réessayer le téléchargement',
          size: _size,
          onPressed: _start,
        );
    }
  }
}

/// Bouton de la fiche série, sous les saisons : télécharger toute la
/// saison (ou les épisodes qui manquent), suivre l'avancée, ou supprimer
/// la saison une fois téléchargée.
class SeasonDownloadButton extends StatelessWidget {
  const SeasonDownloadButton({
    super.key,
    required this.api,
    required this.userId,
    required this.seasonName,
    required this.episodes,
  });

  final JellyfinApi api;
  final String userId;

  /// Nom de la saison (« Saison 5 »).
  final String seasonName;
  final List<Episode> episodes;

  Future<void> _start(BuildContext context, SeasonDownloadSummary s) async {
    final count = s.missingIds.length;
    final size = formatFileSize(s.missingBytes);
    final kept = s.completeIds.isEmpty
        ? ''
        : ' Les ${s.completeIds.length} épisodes déjà téléchargés sont '
              'gardés.';
    final confirmed = await showConfirmDialog(
      context,
      title: 'Télécharger « $seasonName » ?',
      message:
          '$count épisode${count > 1 ? 's' : ''}'
          '${size == null ? '' : ', environ $size'}.$kept Le téléchargement '
          'se fait en Wi-Fi, deux épisodes à la fois.',
      action: 'Télécharger',
      cancel: 'Plus tard',
    );
    if (!confirmed) return;
    await DownloadManager.instance.startAll(
      api: api,
      userId: userId,
      itemIds: s.missingIds,
    );
  }

  Future<void> _stop(BuildContext context, SeasonDownloadSummary s) async {
    final count = s.pendingIds.length;
    if (await showConfirmDialog(
      context,
      title: 'Arrêter les téléchargements de la saison ?',
      message:
          '$count épisode${count > 1 ? 's' : ''} en cours ou en attente '
          'seront annulés. Les épisodes déjà téléchargés sont gardés.',
      action: 'Arrêter',
    )) {
      await DownloadManager.instance.removeAll(s.pendingIds);
    }
  }

  Future<void> _delete(BuildContext context, SeasonDownloadSummary s) async {
    if (await showConfirmDialog(
      context,
      title: 'Supprimer « $seasonName » du téléphone ?',
      message:
          'Les épisodes seront effacés du téléphone. Ils restent '
          'disponibles sur le serveur.',
      action: 'Supprimer',
    )) {
      await DownloadManager.instance.removeAll(s.completeIds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = DownloadManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final s = SeasonDownloadSummary.of(episodes, manager.stateOf);
        final String key;
        final Widget child;
        if (s.isDownloading) {
          key = 'active';
          child = Row(
            children: [
              Expanded(
                child: ProgressPill(
                  progress: s.progress,
                  label:
                      '$seasonName · ${s.completeIds.length} / ${s.tracked} '
                      'téléchargés',
                  detail: '${(s.progress * 100).floor()} %',
                ),
              ),
              const SizedBox(width: 10),
              GlassCircleButton(
                icon: Icons.close_rounded,
                tooltip: 'Arrêter les téléchargements de la saison',
                size: 48,
                onPressed: () => _stop(context, s),
              ),
            ],
          );
        } else if (s.isComplete) {
          key = 'done';
          final size = formatFileSize(s.completeBytes);
          child = Row(
            children: [
              Expanded(
                child: DonePill(
                  label: size == null
                      ? 'Saison téléchargée'
                      : 'Saison téléchargée · $size',
                ),
              ),
              const SizedBox(width: 10),
              GlassCircleButton(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Supprimer la saison du téléphone',
                size: 48,
                onPressed: () => _delete(context, s),
              ),
            ],
          );
        } else {
          final count = s.missingIds.length;
          final size = formatFileSize(s.missingBytes);
          final label = s.completeIds.isEmpty
              ? 'Télécharger la saison'
              : 'Télécharger les $count épisodes restants';
          key = 'start';
          child = OutlinedButton.icon(
            onPressed: () => _start(context, s),
            icon: const Icon(Icons.download_rounded, size: 22),
            label: Text(
              size == null ? label : '$label · $size',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }
        return AnimatedSwitcher(
          duration: AppDurations.medium,
          transitionBuilder: _crossFade,
          child: KeyedSubtree(key: ValueKey(key), child: child),
        );
      },
    );
  }
}

/// Bouton « Téléchargements » de l'en-tête de la bibliothèque : un anneau
/// montre l'avancée des téléchargements en cours, une pastille leur nombre.
/// [onPressed] reçoit le centre du bouton (pour ouvrir l'écran en cercle).
class DownloadsButton extends StatelessWidget {
  const DownloadsButton({super.key, required this.onPressed});

  final ValueChanged<Offset> onPressed;

  @override
  Widget build(BuildContext context) {
    final manager = DownloadManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final count = manager.activeCount;
        final progress = manager.activeProgress ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            GlassCircleButton(
              icon: Icons.download_rounded,
              tooltip: count == 0
                  ? 'Téléchargements'
                  : 'Téléchargements, $count en cours',
              onPressed: () {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                onPressed(box.localToGlobal(box.size.center(Offset.zero)));
              },
            ),
            // Anneau d'avancée autour du bouton
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: count > 0 ? 1 : 0,
                  duration: AppDurations.medium,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: progress),
                    duration: AppDurations.medium,
                    builder: (context, value, _) =>
                        CustomPaint(painter: _RingPainter(value)),
                  ),
                ),
              ),
            ),
            // Pastille avec le nombre : apparaît avec un rebond, le chiffre aussi
            Positioned(
              top: -4,
              right: -4,
              child: IgnorePointer(
                child: AnimatedScale(
                  scale: count > 0 ? 1 : 0,
                  duration: AppDurations.medium,
                  curve: Curves.easeOutBack,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    alignment: Alignment.center,
                    child: AnimatedSwitcher(
                      duration: AppDurations.medium,
                      switchInCurve: Curves.easeOutBack,
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: Text(
                        '${math.max(count, 1)}',
                        key: ValueKey(count),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.black,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Anneau fin autour d'un bouton rond, rempli de [progress] (0 à 1).
class _RingPainter extends CustomPainter {
  const _RingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 + 1,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      paint..color = AppColors.glassStrong,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      paint..color = AppColors.white,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// Petite coche blanche sur une affiche de la bibliothèque quand le film
/// est téléchargé (apparaît avec un rebond).
class DownloadedMark extends StatefulWidget {
  const DownloadedMark({super.key, required this.itemId});

  final String itemId;

  @override
  State<DownloadedMark> createState() => _DownloadedMarkState();
}

class _DownloadedMarkState extends State<DownloadedMark> {
  final _manager = DownloadManager.instance;
  late bool _done = _isDone();

  bool _isDone() =>
      _manager.stateOf(widget.itemId).phase == DownloadPhase.complete;

  // Reconstruit seulement quand la coche change (pas à chaque pour cent)
  void _onChange() {
    final done = _isDone();
    if (done != _done) setState(() => _done = done);
  }

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onChange);
  }

  @override
  void didUpdateWidget(DownloadedMark old) {
    super.didUpdateWidget(old);
    if (old.itemId != widget.itemId) _done = _isDone();
  }

  @override
  void dispose() {
    _manager.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _done ? 1 : 0,
      duration: AppDurations.medium,
      curve: Curves.easeOutBack,
      child: const CircleAvatar(
        radius: 11,
        backgroundColor: AppColors.white,
        child: Icon(
          Icons.download_done_rounded,
          size: 14,
          color: AppColors.black,
        ),
      ),
    );
  }
}
