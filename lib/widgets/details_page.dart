import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/item_details.dart';
import '../models/media_item.dart';
import '../theme/app_theme.dart';
import 'poster_image.dart';
import 'ui.dart';

/// Squelette commun des fiches (film, série) : grande image de fond qui
/// défile plus lentement que le contenu, en-tête ([header]) posé dessus,
/// puis le contenu [children]. Une barre en verre dépoli avec le titre
/// apparaît quand on fait défiler.
class DetailsPage extends StatefulWidget {
  const DetailsPage({
    super.key,
    required this.api,
    required this.item,
    required this.details,
    required this.showBackdropFallback,
    required this.header,
    required this.children,
  });

  final JellyfinApi api;
  final MediaItem item;

  /// Fiche complète (null tant qu'elle charge).
  final ItemDetails? details;

  /// Vrai quand on peut montrer l'image de secours (affiche floutée) :
  /// pas pendant le chargement, sinon elle clignoterait.
  final bool showBackdropFallback;

  /// En-tête posé sur le bas de l'image de fond (affiche, titre, infos).
  final Widget header;

  final List<Widget> children;

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  /// Hauteur de l'image de fond.
  static const _backdropHeight = 420.0;

  /// Position de l'en-tête : il chevauche le bas de l'image.
  static const _headerTop = 290.0;

  final _scrollController = ScrollController();

  /// Vrai quand l'image est passée : on affiche la barre avec le titre.
  bool _showBar = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scrollController.offset > _headerTop - 40;
    if (show != _showBar) setState(() => _showBar = show);
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: GlowBackground(
        center: const Alignment(0.9, -0.2),
        child: Stack(
          children: [
            CustomScrollView(
              controller: _scrollController,
              // Le contenu passe au-dessus de l'en-tête : l'ombre de
              // l'affiche ne déborde pas sur le bouton Lecture
              paintOrder: SliverPaintOrder.lastIsTop,
              slivers: [
                SliverToBoxAdapter(
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: _backdropHeight,
                        // Effet de profondeur : l'image défile moins vite
                        child: AnimatedBuilder(
                          animation: _scrollController,
                          builder: (context, child) {
                            final offset = _scrollController.hasClients
                                ? math.max(0.0, _scrollController.offset)
                                : 0.0;
                            return Transform.translate(
                              offset: Offset(0, offset * 0.45),
                              child: child,
                            );
                          },
                          child: _Backdrop(
                            api: widget.api,
                            item: widget.item,
                            details: widget.details,
                            showFallback: widget.showBackdropFallback,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          _headerTop,
                          20,
                          0,
                        ),
                        child: widget.header,
                      ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 48),
                  sliver: SliverList.list(children: widget.children),
                ),
              ],
            ),
            // Barre du haut en verre dépoli, visible une fois l'image passée
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _showBar ? 1 : 0,
                  duration: AppDurations.fast,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        height: topInset + 60,
                        padding: EdgeInsets.fromLTRB(76, topInset, 20, 0),
                        alignment: Alignment.centerLeft,
                        color: AppColors.scrim70,
                        child: Text(
                          widget.item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: topInset + 8,
              left: 16,
              child: GlassCircleButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Retour',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Image de fond en haut de la fiche, fondue dans le noir.
/// S'il n'y en a pas, l'affiche très floutée.
class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.api,
    required this.item,
    required this.details,
    required this.showFallback,
  });

  final JellyfinApi api;
  final MediaItem item;
  final ItemDetails? details;
  final bool showFallback;

  @override
  Widget build(BuildContext context) {
    // Largeur de l'écran en vrais pixels, arrondie (même adresse = cache)
    final pixels =
        MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    final width = ((pixels / 200).ceil() * 200).clamp(400, 1920);

    final backdropUrl = details == null
        ? null
        : api.backdropUrl(details!, width: width);

    final Widget image;
    if (backdropUrl != null) {
      image = CachedNetworkImage(
        imageUrl: backdropUrl,
        fit: BoxFit.cover,
        fadeInDuration: AppDurations.medium,
        placeholder: (_, _) => const SizedBox.shrink(),
        errorWidget: (_, _, _) => _blurredPoster(),
      );
    } else if (showFallback) {
      image = _blurredPoster();
    } else {
      image = const SizedBox.shrink();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // L'image elle-même devient transparente vers le bas : elle se fond
        // dans le fond de la page, sans ligne de séparation
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, 0.45, 1],
            colors: [AppColors.white, AppColors.white, Colors.transparent],
          ).createShader(bounds),
          child: image,
        ),
        // Voile en haut : barre d'état et bouton retour restent lisibles
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.3],
              colors: [AppColors.scrim55, Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }

  /// L'affiche, très floutée, pour remplir le haut de la fiche.
  Widget _blurredPoster() {
    final url = api.posterUrl(item, width: PosterImage.pixelWidth);
    if (url == null) return const SizedBox.shrink();
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth: PosterImage.pixelWidth,
        placeholder: (_, _) => const SizedBox.shrink(),
        errorWidget: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// En-tête : affiche, titre en grand, ligne d'infos (ex. « 2019 · 1 h 59 »),
/// la note, et des pastilles (ex. qualité du fichier).
class DetailsHeader extends StatelessWidget {
  const DetailsHeader({
    super.key,
    required this.api,
    required this.item,
    this.infos = const [],
    this.rating,
    this.chips = const [],
  });

  final JellyfinApi api;
  final MediaItem item;
  final List<String> infos;
  final String? rating;
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 118,
          height: 177,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.poster),
            boxShadow: const [
              BoxShadow(
                color: AppColors.scrim70,
                blurRadius: 40,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Hero(
            tag: PosterImage.heroTag(item),
            child: PosterImage(api: api, item: item),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: textTheme.displaySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (infos.isNotEmpty)
                    Text(
                      joinInfos(infos),
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.grey,
                      ),
                    ),
                  if (rating != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 17,
                          color: AppColors.white,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          rating!,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final label in chips) OutlinePill(label)],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Genres (en pastilles) puis résumé.
class DetailsOverview extends StatelessWidget {
  const DetailsOverview({super.key, required this.details});

  final ItemDetails details;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final overview = details.overview?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (details.genres.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final genre in details.genres) Chip(label: Text(genre)),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Text(
          overview.isEmpty ? 'Pas de résumé disponible.' : overview,
          style: textTheme.bodyLarge?.copyWith(
            color: overview.isEmpty ? AppColors.grey : AppColors.textSoft,
          ),
        ),
      ],
    );
  }
}

/// Zones grises animées à la place des genres et du résumé, pendant le
/// chargement de la fiche.
class DetailsOverviewSkeleton extends StatelessWidget {
  const DetailsOverviewSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SkeletonBox(width: 80, height: 32, radius: AppRadius.pill),
            SizedBox(width: 8),
            SkeletonBox(width: 96, height: 32, radius: AppRadius.pill),
          ],
        ),
        SizedBox(height: 18),
        SkeletonBox(height: 14, radius: 6),
        SizedBox(height: 10),
        SkeletonBox(height: 14, radius: 6),
        SizedBox(height: 10),
        SkeletonBox(width: 200, height: 14, radius: 6),
      ],
    );
  }
}

/// Message d'erreur avec un bouton « Réessayer ».
class RetryMessage extends StatelessWidget {
  const RetryMessage({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    );
  }
}
