import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/media_item.dart';
import '../models/session.dart';
import '../theme/app_theme.dart';
import 'download_controls.dart';
import 'poster_image.dart';
import 'ui.dart';

/// Grille d'affiches d'un type d'élément (films ou séries), chargée page par
/// page au fil du défilement. Garde sa position quand on change d'onglet.
/// Triée par titre, ou par [sortBy] (« Tout voir » de l'accueil).
class LibraryGrid extends StatefulWidget {
  const LibraryGrid({
    super.key,
    required this.api,
    required this.session,
    required this.itemType,
    required this.emptyMessage,
    required this.topPadding,
    required this.onOpen,
    required this.onUnauthorized,
    this.controller,
    this.bottomPadding = 0,
    this.sortBy,
    this.releasedBefore,
  });

  final JellyfinApi api;
  final Session session;

  /// Type d'élément pour le serveur : « Movie » ou « Series ».
  final String itemType;

  /// Message affiché si la bibliothèque est vide.
  final String emptyMessage;

  /// Espace laissé en haut pour l'en-tête qui passe par-dessus la grille.
  final double topPadding;

  /// Appelé quand on touche une affiche.
  final void Function(MediaItem item) onOpen;

  /// Appelé si le serveur refuse le jeton (retour à la connexion).
  final VoidCallback onUnauthorized;

  /// Défilement (ex. pour remonter en haut d'un appui sur l'onglet).
  final ScrollController? controller;

  /// Espace laissé en bas pour la barre de navigation.
  final double bottomPadding;

  /// Tri du plus récent au plus ancien (« DateCreated », « PremiereDate »),
  /// et seulement les éléments déjà sortis à [releasedBefore].
  final String? sortBy;
  final DateTime? releasedBefore;

  @override
  State<LibraryGrid> createState() => _LibraryGridState();
}

class _LibraryGridState extends State<LibraryGrid>
    with AutomaticKeepAliveClientMixin {
  /// Nombre d'éléments demandés à chaque fois.
  static const _pageSize = 50;

  /// On charge la suite quand il reste moins de cette distance à défiler.
  static const _loadMoreThreshold = 800.0;

  late final _scrollController = widget.controller ?? ScrollController();
  final List<MediaItem> _items = [];

  /// Nombre total d'éléments sur le serveur (null tant qu'on ne le connaît pas).
  int? _totalCount;
  bool _loading = false;
  String? _error;

  bool get _hasMore => _totalCount == null || _items.length < _totalCount!;

  /// Garde la grille en mémoire quand on passe à l'autre onglet.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    // Défilement fourni par l'écran : c'est lui qui le libère
    if (widget.controller == null) _scrollController.dispose();
    super.dispose();
  }

  /// Arrivé près du bas de la grille : on charge la page suivante.
  /// En cas d'erreur, on attend que l'utilisateur appuie sur « Réessayer ».
  void _onScroll() {
    if (_error == null &&
        _scrollController.position.extentAfter < _loadMoreThreshold) {
      _loadMore();
    }
  }

  /// Charge la page suivante et l'ajoute à la grille.
  /// Avec [reset], recharge la première page et remplace toute la grille.
  Future<void> _loadMore({bool reset = false}) async {
    if (_loading || (!reset && !_hasMore)) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final page = await widget.api.getItems(
        userId: widget.session.userId,
        type: widget.itemType,
        startIndex: reset ? 0 : _items.length,
        limit: _pageSize,
        sortBy: widget.sortBy,
        releasedBefore: widget.releasedBefore,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _totalCount = page.totalCount;
        // Sécurité : le serveur n'a plus rien à donner
        if (page.items.isEmpty) _totalCount = _items.length;
      });
    } on JellyfinException catch (e) {
      if (e.isUnauthorized) {
        // Jeton révoqué pendant l'utilisation : retour à la connexion
        widget.onUnauthorized();
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Tirer vers le bas : on recharge depuis le début.
  Future<void> _refresh() => _loadMore(reset: true);

  /// Grille commune : vraies affiches, ou zones grises pendant le chargement.
  static const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    // 3 colonnes sur un téléphone, davantage sur une tablette
    maxCrossAxisExtent: 150,
    childAspectRatio: 0.55,
    crossAxisSpacing: 12,
    mainAxisSpacing: 18,
  );

  @override
  Widget build(BuildContext context) {
    super.build(context); // nécessaire pour AutomaticKeepAliveClientMixin
    final padding = EdgeInsets.fromLTRB(16, widget.topPadding + 12, 16, 12);

    // Premier chargement : la grille a déjà sa forme, en zones grises
    if (_items.isEmpty && _loading) {
      return GridView.builder(
        padding: EdgeInsets.fromLTRB(16, widget.topPadding + 12, 16, 12),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: _gridDelegate,
        itemCount: 12,
        itemBuilder: (_, _) => const _PosterTileSkeleton(),
      );
    }
    // Premier chargement raté
    if (_items.isEmpty && _error != null) {
      return _MessageView(
        topPadding: widget.topPadding,
        icon: Icons.cloud_off_rounded,
        message: _error!,
        onRetry: _loadMore,
      );
    }
    // Bibliothèque vide
    if (_items.isEmpty && !_hasMore) {
      return _MessageView(
        topPadding: widget.topPadding,
        icon: Icons.movie_outlined,
        message: widget.emptyMessage,
        onRetry: _refresh,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      // La roue apparaît sous l'en-tête, pas derrière
      edgeOffset: widget.topPadding,
      child: CustomScrollView(
        controller: _scrollController,
        // Permet de tirer pour rafraîchir même avec peu d'éléments
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: padding,
            sliver: SliverGrid.builder(
              // Le nombre de colonnes s'adapte à la largeur de l'écran
              gridDelegate: _gridDelegate,
              itemCount: _items.length,
              itemBuilder: (context, index) => _PosterTile(
                api: widget.api,
                item: _items[index],
                onTap: () => widget.onOpen(_items[index]),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildFooter()),
        ],
      ),
    );
  }

  /// Bas de la grille : roue de chargement, ou erreur avec « Réessayer ».
  Widget _buildFooter() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadMore,
              child: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }
    if (_hasMore) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(0, 8, 0, 32),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    return SizedBox(
      height: MediaQuery.paddingOf(context).bottom + widget.bottomPadding + 24,
    );
  }
}

/// Une case de la grille : affiche (avec une ombre douce), titre et année.
class _PosterTile extends StatelessWidget {
  const _PosterTile({
    required this.api,
    required this.item,
    required this.onTap,
  });

  final JellyfinApi api;
  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // L'affiche prend toute la place restante, et « glisse » vers la fiche
          Expanded(
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: PosterImage.heroTag(item),
                    child: PosterImage(api: api, item: item),
                  ),
                  // Film téléchargé : petite coche en haut à droite
                  if (!item.isSeries)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: DownloadedMark(itemId: item.id),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          // Texte vide si pas d'année : toutes les cases gardent la même hauteur
          Text(
            item.year?.toString() ?? '',
            maxLines: 1,
            style: textTheme.bodySmall?.copyWith(color: AppColors.grey),
          ),
        ],
      ),
    );
  }
}

/// Case en zones grises animées, pendant le premier chargement.
class _PosterTileSkeleton extends StatelessWidget {
  const _PosterTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: SkeletonBox()),
        SizedBox(height: 10),
        SkeletonBox(width: 90, height: 12, radius: 6),
        SizedBox(height: 6),
        SkeletonBox(width: 40, height: 10, radius: 5),
      ],
    );
  }
}

/// Message plein écran avec un bouton « Réessayer ».
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.topPadding,
    required this.icon,
    required this.message,
    required this.onRetry,
  });

  final double topPadding;
  final IconData icon;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(32, topPadding, 32, 0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.grey),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
