import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/media_item.dart';
import '../theme/app_theme.dart';
import 'poster_image.dart';
import 'ui.dart';

/// Tailles de la page d'accueil : affiches plus grandes et marges plus
/// larges sur une tablette.
class HomeLayout {
  const HomeLayout._(this.isWide);

  factory HomeLayout.of(BuildContext context) =>
      HomeLayout._(MediaQuery.sizeOf(context).width >= 700);

  /// Vrai sur une tablette (ou un grand écran).
  final bool isWide;

  /// Largeur d'une affiche dans une rangée.
  double get posterWidth => isWide ? 148 : 112;

  /// Marge à gauche et à droite.
  double get gutter => isWide ? 40 : 20;
}

/// Rangée de l'accueil : titre (avec « Tout voir » si [onSeeAll]), puis
/// des affiches qui défilent de gauche à droite.
class MediaRow extends StatelessWidget {
  const MediaRow({
    super.key,
    required this.title,
    required this.children,
    this.onSeeAll,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayout.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.gutter),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.grey,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: textTheme.labelMedium,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Tout voir'),
                      Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          // Affiche (2:3), puis titre et petite ligne
          height: layout.posterWidth * 1.5 + 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: layout.gutter),
            clipBehavior: Clip.none,
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, index) => children[index],
          ),
        ),
      ],
    );
  }
}

/// Affiche d'une rangée : s'enfonce un peu à l'appui, avec le titre et une
/// petite ligne dessous. [overlays] : posés sur l'affiche (pastille,
/// barre…). [heroTag] : l'affiche glisse vers la fiche.
class MediaTile extends StatelessWidget {
  const MediaTile({
    super.key,
    required this.api,
    required this.item,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.heroTag,
    this.overlays = const [],
  });

  final JellyfinApi api;

  /// Élément dont on montre l'affiche.
  final MediaItem item;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? heroTag;
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final width = HomeLayout.of(context).posterWidth;
    Widget poster = PosterImage(api: api, item: item);
    if (heroTag != null) poster = Hero(tag: heroTag!, child: poster);
    return PressableScale(
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
                    children: [poster, ...overlays],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              subtitle,
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

/// Petite pastille sur une affiche (« Nouvel épisode », « 3 nouveaux »).
class PosterChip extends StatelessWidget {
  const PosterChip(this.label, {super.key, this.right = false});

  final String label;

  /// En haut à droite (sinon à gauche).
  final bool right;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 7,
      left: right ? null : 7,
      right: right ? 7 : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.black,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Rangée en zones grises animées, pendant le chargement.
class MediaRowSkeleton extends StatelessWidget {
  const MediaRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayout.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.gutter),
          child: const SkeletonBox(width: 160, height: 18, radius: 6),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: layout.posterWidth * 1.5 + 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: layout.gutter),
            itemCount: 8,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(
                  width: layout.posterWidth,
                  height: layout.posterWidth * 1.5,
                ),
                const SizedBox(height: 10),
                SkeletonBox(
                  width: layout.posterWidth * 0.8,
                  height: 12,
                  radius: 6,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
