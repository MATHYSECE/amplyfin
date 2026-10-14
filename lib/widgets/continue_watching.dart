import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/resume_entry.dart';
import '../services/device_capabilities.dart';
import '../services/download_manager.dart';
import '../theme/app_theme.dart';
import 'media_row.dart';
import 'ui.dart';

/// Choix du panneau ouvert par un appui long sur une affiche de la rangée.
enum ResumeAction { resume, restart, openDetails, markPlayed, download, remove }

/// Façon de retirer une entrée de « Continuer à regarder ».
enum ResumeRemoval {
  /// Masquée sur cet appareil, la progression est gardée.
  keepProgress,

  /// Progression effacée sur le serveur, comme jamais regardé.
  reset,
}

/// Nom de l'animation de l'affiche d'une entrée vers sa fiche.
String resumeHeroTag(ResumeEntry entry) => 'home-continue-${entry.id}';

/// Rangée « Continuer à regarder » de l'accueil, comme sur Netflix : les
/// films et épisodes commencés (temps restant, barre de progression) et
/// l'épisode suivant des séries en cours (« Épisode suivant », « Nouvel
/// épisode »). Un appui lance la lecture, un appui long ouvre les autres
/// choix ([onOptions]). Rien n'est affiché s'il n'y a rien en cours.
class ContinueWatchingRow extends StatelessWidget {
  const ContinueWatchingRow({
    super.key,
    required this.api,
    required this.entries,
    required this.onPlay,
    required this.onOptions,
  });

  final JellyfinApi api;
  final List<ResumeEntry> entries;
  final void Function(ResumeEntry entry) onPlay;

  /// Appui long : reprendre, depuis le début, aller à la fiche, ou retirer
  /// de la rangée.
  final void Function(ResumeEntry entry) onOptions;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return MediaRow(
      title: 'Continuer à regarder',
      children: [
        for (final entry in entries)
          MediaTile(
            key: ValueKey(entry.id),
            api: api,
            item: entry.poster,
            title: entry.title,
            subtitle: entry.subtitle,
            heroTag: resumeHeroTag(entry),
            onTap: () => onPlay(entry),
            onLongPress: () => onOptions(entry),
            overlays: _overlays(context, entry),
          ),
      ],
    );
  }

  /// Bouton lecture au centre ; temps restant et barre en bas (commencé),
  /// ou pastille « Épisode suivant » en haut (pas encore commencé).
  List<Widget> _overlays(BuildContext context, ResumeEntry entry) {
    final remaining = entry.remainingLabel;
    return [
      // Voile en bas : texte lisible sur toute affiche
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.55, 1],
            colors: [Colors.transparent, AppColors.scrim70],
          ),
        ),
      ),
      const Center(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: AppColors.scrim55,
            shape: CircleBorder(
              side: BorderSide(color: AppColors.outlineStrong),
            ),
          ),
          child: SizedBox.square(
            dimension: 40,
            child: Icon(
              Icons.play_arrow_rounded,
              size: 22,
              color: AppColors.white,
            ),
          ),
        ),
      ),
      if (entry.nextLabel case final label?)
        PosterChip(label)
      else ...[
        if (remaining != null)
          Positioned(
            left: 8,
            bottom: 9,
            child: Text(
              remaining,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: AppColors.textSoft),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ProgressLine(value: entry.progress.fraction),
        ),
      ],
    ];
  }
}

/// Panneau de l'appui long sur une affiche : le titre, puis « Reprendre
/// à … », « Depuis le début », « Aller à la page du film / de la série »,
/// « Marquer comme vu », « Télécharger » (pas sur télé) et « Retirer de
/// Continuer à regarder ». Pour un épisode suivant (pas encore commencé) :
/// ni « Depuis le début », ni « Retirer ».
/// Renvoie le choix, ou null si on ferme le panneau.
Future<ResumeAction?> showResumeActions(
  BuildContext context,
  ResumeEntry entry,
) {
  return showModalBottomSheet<ResumeAction>(
    context: context,
    // Plus haut que la moitié de l'écran si besoin (télé, paysage), et
    // défilant s'il manque encore de place
    isScrollControlled: true,
    builder: (context) {
      void choose(ResumeAction action) => Navigator.of(context).pop(action);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  entry.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(
                  [
                    if (entry.subtitle.isNotEmpty) entry.subtitle,
                    ?entry.nextLabel,
                  ].join(' · '),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: Text(
                  entry.isNext ? 'Lire l\'épisode' : entry.progress.resumeLabel,
                ),
                onTap: () => choose(ResumeAction.resume),
              ),
              if (!entry.isNext)
                ListTile(
                  leading: const Icon(Icons.replay_rounded),
                  title: const Text('Depuis le début'),
                  onTap: () => choose(ResumeAction.restart),
                ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(
                  entry.isEpisode
                      ? 'Aller à la page de la série'
                      : 'Aller à la page du film',
                ),
                onTap: () => choose(ResumeAction.openDetails),
              ),
              ListTile(
                leading: const Icon(Icons.check_rounded),
                title: const Text('Marquer comme vu'),
                onTap: () => choose(ResumeAction.markPlayed),
              ),
              // Télé : pas de téléchargements
              if (!DeviceCapabilities.isTv)
                _DownloadTile(
                  itemId: entry.id,
                  onTap: () => choose(ResumeAction.download),
                ),
              if (!entry.isNext) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline_rounded),
                  title: const Text('Retirer de Continuer à regarder'),
                  onTap: () => choose(ResumeAction.remove),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Ligne « Télécharger » du panneau, selon l'état du téléchargement : rien
/// d'autre à faire s'il est déjà en cours ou terminé.
class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.itemId, required this.onTap});

  final String itemId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final manager = DownloadManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) => switch (manager.stateOf(itemId).phase) {
        DownloadPhase.complete => const ListTile(
          enabled: false,
          leading: Icon(Icons.download_done_rounded),
          title: Text('Téléchargé'),
        ),
        DownloadPhase.waiting ||
        DownloadPhase.running ||
        DownloadPhase.paused => const ListTile(
          enabled: false,
          leading: Icon(Icons.downloading_rounded),
          title: Text('Téléchargement en cours'),
        ),
        DownloadPhase.failed => ListTile(
          leading: const Icon(Icons.download_rounded),
          title: const Text('Réessayer le téléchargement'),
          onTap: onTap,
        ),
        DownloadPhase.none => ListTile(
          leading: const Icon(Icons.download_rounded),
          title: const Text('Télécharger'),
          onTap: onTap,
        ),
      },
    );
  }
}

/// « Retirer de Continuer à regarder » : garder la progression (l'entrée
/// est seulement masquée) ou tout remettre à zéro. Null si on ferme.
Future<ResumeRemoval?> showResumeRemoval(
  BuildContext context,
  ResumeEntry entry,
) {
  return showModalBottomSheet<ResumeRemoval>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      void choose(ResumeRemoval removal) => Navigator.of(context).pop(removal);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Retirer « ${entry.title} »',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ListTile(
                autofocus: DeviceCapabilities.isTv,
                leading: const Icon(Icons.bookmark_outline_rounded),
                title: const Text('Garder ma progression'),
                subtitle: const Text(
                  'Retiré de la rangée ; reprend au même endroit si tu le '
                  'relances',
                ),
                onTap: () => choose(ResumeRemoval.keepProgress),
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: const Text('Tout remettre à zéro'),
                subtitle: const Text(
                  'La progression est effacée, comme si tu ne l\'avais pas '
                  'regardé',
                ),
                onTap: () => choose(ResumeRemoval.reset),
              ),
            ],
          ),
        ),
      );
    },
  );
}
