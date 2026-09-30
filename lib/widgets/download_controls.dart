import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/file_size.dart';
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

/// Demande confirmation avant une action sur un téléchargement.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Garder'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Annule un téléchargement en cours (après confirmation).
Future<void> _cancel(BuildContext context, String itemId) async {
  if (await _confirm(
    context,
    title: 'Annuler le téléchargement ?',
    message: 'La partie déjà téléchargée sera effacée du téléphone.',
    action: 'Annuler le téléchargement',
  )) {
    await DownloadManager.instance.remove(itemId);
  }
}

/// Supprime un téléchargement terminé (après confirmation).
Future<void> _delete(BuildContext context, String itemId) async {
  if (await _confirm(
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
        final textTheme = Theme.of(context).textTheme;
        switch (state.phase) {
          case DownloadPhase.none:
            final size = formatFileSize(fileSize);
            return OutlinedButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.download_rounded, size: 22),
              label: Text(
                compact || size == null ? 'Télécharger' : 'Télécharger · $size',
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
                  child: _ProgressPill(
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
                  onPressed: () => _cancel(context, itemId),
                ),
              ],
            );
          case DownloadPhase.complete:
            final size = formatFileSize(state.size);
            return Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48,
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
                        Text(
                          size == null ? 'Téléchargé' : 'Téléchargé · $size',
                          style: textTheme.labelLarge,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GlassCircleButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Supprimer le téléchargement',
                  size: 48,
                  onPressed: () => _delete(context, itemId),
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
      },
    );
  }
}

/// Pilule qui se remplit de gauche à droite pendant le téléchargement.
class _ProgressPill extends StatelessWidget {
  const _ProgressPill({
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
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: const ColoredBox(color: AppColors.glassStrong),
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

/// Rond de téléchargement d'un épisode (à côté du bouton ⓘ) :
/// ⬇ à télécharger, cercle qui se remplit pendant le téléchargement (un
/// appui l'annule), rond blanc ✓ une fois téléchargé (un appui propose de
/// supprimer), ou ↻ pour réessayer après un échec.
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
                onTap: () => _cancel(context, itemId),
                radius: _size / 2,
                child: SizedBox.square(
                  dimension: _size,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.square(
                        dimension: _size - 4,
                        child: CircularProgressIndicator(
                          // En attente : cercle qui tourne sans progression
                          value: state.phase == DownloadPhase.waiting
                              ? null
                              : state.progress,
                          strokeWidth: 2.5,
                          backgroundColor: AppColors.track,
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
                  onTap: () => _delete(context, itemId),
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
      },
    );
  }
}
