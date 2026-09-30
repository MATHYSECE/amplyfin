import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/item_details.dart';
import '../models/media_item.dart';
import 'poster_image.dart';

/// Squelette commun des fiches (film, série) : image de fond repliable en
/// haut, puis le contenu [children] en dessous. Quand l'image est repliée,
/// le titre apparaît dans la barre du haut.
class DetailsPage extends StatefulWidget {
  const DetailsPage({
    super.key,
    required this.api,
    required this.item,
    required this.details,
    required this.showBackdropFallback,
    required this.children,
  });

  final JellyfinApi api;
  final MediaItem item;

  /// Fiche complète (null tant qu'elle charge).
  final ItemDetails? details;

  /// Vrai quand on peut montrer l'image de secours (affiche floutée) :
  /// pas pendant le chargement, sinon elle clignoterait.
  final bool showBackdropFallback;

  final List<Widget> children;

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  /// Hauteur de l'image de fond quand elle est dépliée.
  static const _backdropHeight = 240.0;

  final _scrollController = ScrollController();

  /// Vrai quand l'image de fond est repliée : on montre alors le titre en haut.
  bool _showTitle = false;

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
    final show = _scrollController.offset > _backdropHeight - kToolbarHeight;
    if (show != _showTitle) setState(() => _showTitle = show);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: _backdropHeight,
            title: AnimatedOpacity(
              opacity: _showTitle ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Text(widget.item.name),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _Backdrop(
                api: widget.api,
                item: widget.item,
                details: widget.details,
                showFallback: widget.showBackdropFallback,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            sliver: SliverList.list(children: widget.children),
          ),
        ],
      ),
    );
  }
}

/// Image de fond en haut de la fiche. S'il n'y en a pas, l'affiche floutée.
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
    final colors = Theme.of(context).colorScheme;

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
        fadeInDuration: const Duration(milliseconds: 300),
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
        image,
        // Dégradé : lisibilité de la barre du haut, et fondu vers la page
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.35, 0.6, 1],
              colors: [
                colors.surface.withValues(alpha: 0.6),
                colors.surface.withValues(alpha: 0),
                colors.surface.withValues(alpha: 0),
                colors.surface,
              ],
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
      imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
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

/// En-tête : petite affiche, titre, ligne d'infos (ex. « 2019 · 1 h 59 »),
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
    final colors = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Hero(
              tag: PosterImage.heroTag(item),
              child: PosterImage(api: api, item: item),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: textTheme.headlineSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (infos.isNotEmpty)
                    Text(
                      infos.join(' · '),
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  if (rating != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, size: 18, color: colors.primary),
                        const SizedBox(width: 4),
                        Text(rating!, style: textTheme.bodyMedium),
                      ],
                    ),
                ],
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final label in chips)
                      Chip(
                        label: Text(label),
                        labelStyle: textTheme.labelSmall,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
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
    final colors = Theme.of(context).colorScheme;
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
          style: overview.isEmpty
              ? textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant)
              : textTheme.bodyLarge,
        ),
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
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    );
  }
}
