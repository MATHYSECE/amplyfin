import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/movie.dart';
import '../models/session.dart';
import '../services/session_store.dart';
import 'login_screen.dart';

/// Bibliothèque : grille des affiches de films, chargée page par page.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.api, required this.session});

  final JellyfinApi api;
  final Session session;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  /// Nombre de films demandés à chaque fois.
  static const _pageSize = 50;

  /// On charge la suite quand il reste moins de cette distance à défiler.
  static const _loadMoreThreshold = 800.0;

  final _scrollController = ScrollController();
  final List<Movie> _movies = [];

  /// Nombre total de films sur le serveur (null tant qu'on ne le connaît pas).
  int? _totalCount;
  bool _loading = false;
  String? _error;

  bool get _hasMore => _totalCount == null || _movies.length < _totalCount!;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scrollController.dispose();
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

  /// Charge la page de films suivante et l'ajoute à la grille.
  /// Avec [reset], recharge la première page et remplace toute la grille.
  Future<void> _loadMore({bool reset = false}) async {
    if (_loading || (!reset && !_hasMore)) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final page = await widget.api.getMovies(
        userId: widget.session.userId,
        startIndex: reset ? 0 : _movies.length,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _movies.clear();
        _movies.addAll(page.movies);
        _totalCount = page.totalCount;
        // Sécurité : le serveur n'a plus rien à donner
        if (page.movies.isEmpty) _totalCount = _movies.length;
      });
    } on JellyfinException catch (e) {
      if (e.isUnauthorized) {
        // Jeton révoqué pendant l'utilisation : retour à la connexion
        await _backToLogin();
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Tirer vers le bas : on recharge depuis le début.
  Future<void> _refresh() => _loadMore(reset: true);

  Future<void> _logout() async {
    // On prévient le serveur, mais on se déconnecte même s'il est injoignable
    try {
      await widget.api.logout();
    } on JellyfinException {
      // Rien à faire : le jeton sera de toute façon effacé du téléphone
    }
    await _backToLogin();
  }

  /// Efface la session du téléphone et revient à l'écran de connexion.
  Future<void> _backToLogin() async {
    await SessionStore().clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Films'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: _logout,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Premier chargement
    if (_movies.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // Premier chargement raté
    if (_movies.isEmpty && _error != null) {
      return _MessageView(
        icon: Icons.cloud_off,
        message: _error!,
        onRetry: _loadMore,
      );
    }
    // Bibliothèque vide
    if (_movies.isEmpty && !_hasMore) {
      return _MessageView(
        icon: Icons.movie_outlined,
        message: 'Aucun film trouvé sur ce serveur.',
        onRetry: _refresh,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scrollController,
        // Permet de tirer pour rafraîchir même avec peu de films
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid.builder(
              // Le nombre de colonnes s'adapte à la largeur de l'écran
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                childAspectRatio: 0.55,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
              ),
              itemCount: _movies.length,
              itemBuilder: (context, index) =>
                  _MovieTile(api: widget.api, movie: _movies[index]),
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
            const SizedBox(height: 8),
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
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: 24);
  }
}

/// Une case de la grille : affiche, titre et année.
class _MovieTile extends StatelessWidget {
  const _MovieTile({required this.api, required this.movie});

  final JellyfinApi api;
  final Movie movie;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // L'affiche prend toute la place restante ; arrondis via le thème (Card)
        Expanded(
          child: Card(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = _posterPixelWidth(context, constraints.maxWidth);
                final url = api.posterUrl(movie, width: width);
                if (url == null) return const _PosterPlaceholder();
                return CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  // Image décodée à la taille affichée : économise la mémoire
                  memCacheWidth: width,
                  fadeInDuration: const Duration(milliseconds: 200),
                  placeholder: (_, _) => const SizedBox.shrink(),
                  errorWidget: (_, _, _) => const _PosterPlaceholder(),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          movie.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium,
        ),
        // Texte vide si pas d'année : toutes les cases gardent la même hauteur
        Text(
          movie.year?.toString() ?? '',
          maxLines: 1,
          style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Largeur de l'affiche en vrais pixels, arrondie à la centaine supérieure :
  /// le serveur envoie une image juste assez grande, et l'adresse reste la même
  /// d'une case à l'autre (donc le cache sert au maximum).
  static int _posterPixelWidth(BuildContext context, double logicalWidth) {
    final pixels = logicalWidth * MediaQuery.devicePixelRatioOf(context);
    return ((pixels / 100).ceil() * 100).clamp(100, 1000);
  }
}

/// Affichée quand un film n'a pas d'affiche (ou si elle ne charge pas).
class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.movie_outlined,
        size: 40,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Message plein écran avec un bouton « Réessayer ».
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
