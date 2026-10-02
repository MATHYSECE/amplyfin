import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/resume_entry.dart';
import '../theme/app_theme.dart';
import 'media_row.dart';
import 'ui.dart';

/// Choix du panneau ouvert par un appui long sur une affiche de la rangée.
enum ResumeAction { resume, restart, openDetails, markPlayed, remove }

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
/// à … », « Depuis le début », « Aller à la page du film / de la série » et
/// « Retirer de Continuer à regarder ». Pour un épisode suivant (pas encore
/// commencé) : seulement « Lire l'épisode » et la page de la série.
/// Renvoie le choix, ou null si on ferme le panneau.
Future<ResumeAction?> showResumeActions(
  BuildContext context,
  ResumeEntry entry,
) {
  return showModalBottomSheet<ResumeAction>(
    context: context,
    builder: (context) {
      void choose(ResumeAction action) => Navigator.of(context).pop(action);
      return SafeArea(
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
            if (!entry.isNext) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.remove_circle_outline_rounded),
                title: const Text('Retirer de Continuer à regarder'),
                subtitle: const Text(
                  'La progression est effacée, comme si tu ne l\'avais '
                  'pas regardé',
                ),
                onTap: () => choose(ResumeAction.remove),
              ),
            ],
          ],
        ),
      );
    },
  );
}
