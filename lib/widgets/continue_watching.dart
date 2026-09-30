import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/resume_entry.dart';
import '../theme/app_theme.dart';
import 'poster_image.dart';
import 'ui.dart';

/// Choix du panneau ouvert par un appui long sur une affiche de la rangée.
enum ResumeAction { resume, restart, openDetails, remove }

/// Rangée « Continuer à regarder » en haut de la bibliothèque : affiches des
/// films et épisodes commencés, qui défilent de gauche à droite. Un appui
/// reprend la lecture, un appui long ouvre les autres choix ([onOptions]).
/// Suivie du titre de la grille ([gridTitle]).
/// Rien n'est affiché s'il n'y a rien en cours.
class ContinueWatchingRow extends StatelessWidget {
  const ContinueWatchingRow({
    super.key,
    required this.api,
    required this.entries,
    required this.gridTitle,
    required this.onPlay,
    required this.onOptions,
  });

  /// Largeur d'une affiche (même taille que dans la grille d'un téléphone).
  static const _posterWidth = 112.0;

  final JellyfinApi api;
  final List<ResumeEntry> entries;

  /// Titre de la grille qui suit (« Tous les films »…).
  final String gridTitle;

  final void Function(ResumeEntry entry) onPlay;

  /// Appui long : reprendre, depuis le début, aller à la fiche, ou retirer
  /// de la rangée.
  final void Function(ResumeEntry entry) onOptions;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final titleStyle = Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w800);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('Continuer à regarder', style: titleStyle),
        ),
        const SizedBox(height: 12),
        SizedBox(
          // Affiche (2:3), puis titre et petite ligne
          height: _posterWidth * 1.5 + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            clipBehavior: Clip.none,
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _ResumeCard(
              api: api,
              entry: entries[index],
              width: _posterWidth,
              onTap: () => onPlay(entries[index]),
              onLongPress: () => onOptions(entries[index]),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(gridTitle, style: titleStyle),
        ),
      ],
    );
  }
}

/// Une affiche de la rangée : bouton lecture au centre, temps restant et
/// barre de progression en bas, titre et petite ligne dessous.
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.api,
    required this.entry,
    required this.width,
    required this.onTap,
    required this.onLongPress,
  });

  final JellyfinApi api;
  final ResumeEntry entry;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final remaining = entry.remainingLabel;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              height: width * 1.5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.poster),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.scrim55,
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.poster),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PosterImage(api: api, item: entry.poster),
                      // Voile en bas : temps restant lisible sur toute affiche
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
                      // Rond sombre avec ▶ : un appui reprend la lecture
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
                      if (remaining != null)
                        Positioned(
                          left: 8,
                          bottom: 9,
                          child: Text(
                            remaining,
                            style: textTheme.labelSmall?.copyWith(
                              color: AppColors.textSoft,
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ProgressLine(value: entry.progress.fraction),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              entry.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Panneau de l'appui long sur une affiche : le titre, puis « Reprendre
/// à … », « Depuis le début », « Aller à la page du film / de la série » et
/// « Retirer de Continuer à regarder ».
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
              subtitle: entry.subtitle.isEmpty ? null : Text(entry.subtitle),
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: Text(entry.progress.resumeLabel),
              onTap: () => choose(ResumeAction.resume),
            ),
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
        ),
      );
    },
  );
}
