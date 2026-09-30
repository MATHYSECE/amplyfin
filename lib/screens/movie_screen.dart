import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/movie.dart';
import '../models/movie_details.dart';
import '../models/session.dart';
import '../widgets/poster_image.dart';
import 'player_screen.dart';

/// Fiche d'un film : image de fond, affiche, infos, bouton lecture, résumé.
/// Le titre, l'année et l'affiche (déjà connus grâce à la grille) s'affichent
/// tout de suite ; le reste arrive quand le serveur a répondu.
class MovieScreen extends StatefulWidget {
  const MovieScreen({
    super.key,
    required this.api,
    required this.session,
    required this.movie,
  });

  final JellyfinApi api;
  final Session session;
  final Movie movie;

  @override
  State<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> {
  /// Hauteur de l'image de fond quand elle est dépliée.
  static const _backdropHeight = 240.0;

  final _scrollController = ScrollController();

  MovieDetails? _details;
  bool _loading = false;
  String? _error;

  /// Vrai quand l'image de fond est repliée : on montre alors le titre en haut.
  bool _showTitle = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
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

  /// Demande la fiche complète au serveur.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = await widget.api.getMovieDetails(
        userId: widget.session.userId,
        movieId: widget.movie.id,
      );
      if (mounted) setState(() => _details = details);
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _play() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          api: widget.api,
          session: widget.session,
          movie: widget.movie,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;

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
              child: Text(movie.name),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _Backdrop(
                api: widget.api,
                movie: movie,
                details: _details,
                // Tant que la fiche charge, on ne montre pas l'image de secours
                showFallback: !_loading,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(api: widget.api, movie: movie, details: _details),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _play,
                    icon: const Icon(Icons.play_arrow),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Lecture'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildDetails(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Genres et résumé, ou roue de chargement, ou erreur avec « Réessayer ».
  Widget _buildDetails() {
    final details = _details;
    if (details == null) {
      if (_error != null) {
        return Column(
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
          ],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

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

/// Image de fond en haut de la fiche. S'il n'y en a pas, l'affiche floutée.
class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.api,
    required this.movie,
    required this.details,
    required this.showFallback,
  });

  final JellyfinApi api;
  final Movie movie;
  final MovieDetails? details;
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
    final url = api.posterUrl(movie, width: PosterImage.pixelWidth);
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

/// En-tête : petite affiche, titre, et ligne d'infos
/// (année · durée · âge conseillé, puis la note).
class _Header extends StatelessWidget {
  const _Header({
    required this.api,
    required this.movie,
    required this.details,
  });

  final JellyfinApi api;
  final Movie movie;
  final MovieDetails? details;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    final infos = [
      if (movie.year != null) '${movie.year}',
      if (details?.runtimeLabel != null) details!.runtimeLabel!,
      if (details?.officialRating != null) details!.officialRating!,
    ];
    final rating = details?.ratingLabel;
    final qualityLabels = details?.quality?.labels ?? const <String>[];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Hero(
              tag: PosterImage.heroTag(movie),
              child: PosterImage(api: api, movie: movie),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(movie.name, style: textTheme.headlineSmall),
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
                        Text(rating, style: textTheme.bodyMedium),
                      ],
                    ),
                ],
              ),
              // Qualité du fichier : 4K, HEVC, HDR10, E-AC3 5.1…
              if (qualityLabels.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final label in qualityLabels)
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
