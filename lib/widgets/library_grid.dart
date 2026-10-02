import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/genre.dart';
import '../models/media_item.dart';
import '../models/session.dart';
import '../services/connection_monitor.dart';
import '../services/library_preferences.dart';
import '../services/watched_state.dart';
import '../theme/app_theme.dart';
import 'download_controls.dart';
import 'poster_image.dart';
import 'track_picker.dart';
import 'ui.dart';
import 'watched_controls.dart';

/// Grille d'affiches d'un type d'élément (films ou séries), chargée page par
/// page au fil du défilement. Garde sa position quand on change d'onglet.
/// Triée par titre, ou par [sortBy] (« Tout voir » de l'accueil).
/// Avec [showFilters] : genres en pastilles et bouton « Trier » en haut.
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
    this.personId,
    this.genreId,
    this.showFilters = false,
  });

  final JellyfinApi api;
  final Session session;

  /// Type d'élément pour le serveur : « Movie », « Series » (ou les deux).
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

  /// Seulement les films et séries de cette personne (acteur, réalisateur).
  final String? personId;

  /// Seulement les films et séries de ce genre.
  final String? genreId;

  /// Genres en pastilles et bouton « Trier » (onglets Films et Séries).
  final bool showFilters;

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

  /// Affiches déjà apparues (les autres arrivent en fondu).
  final Set<String> _shown = {};

  /// Nombre total d'éléments sur le serveur (null tant qu'on ne le connaît pas).
  int? _totalCount;
  bool _loading = false;
  String? _error;

  /// Numéro de la liste demandée : une réponse pour un ancien genre ou un
  /// ancien tri, arrivée en retard, est ignorée.
  int _generation = 0;

  // Filtres (onglets Films et Séries)
  final _preferences = LibraryPreferences();
  LibrarySort _sort = LibrarySort.title;
  String? _genreId;
  List<Genre>? _genres;

  bool get _hasMore => _totalCount == null || _items.length < _totalCount!;

  /// Garde la grille en mémoire quand on passe à l'autre onglet.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.showFilters) {
      _start();
      ConnectionMonitor.instance.addListener(_onConnection);
    } else {
      _loadMore();
    }
  }

  /// Onglets Films et Séries : tri retenu, puis grille et genres.
  Future<void> _start() async {
    final sort = await _preferences.loadSort(widget.itemType);
    if (!mounted) return;
    setState(() => _sort = sort);
    await Future.wait([_loadMore(), _loadGenres()]);
  }

  @override
  void dispose() {
    if (widget.showFilters) {
      ConnectionMonitor.instance.removeListener(_onConnection);
    }
    // Défilement fourni par l'écran : c'est lui qui le libère
    if (widget.controller == null) _scrollController.dispose();
    super.dispose();
  }

  /// La connexion revient : les genres (s'ils manquaient) arrivent.
  void _onConnection() {
    if (_genres == null && ConnectionMonitor.instance.online) _loadGenres();
  }

  Future<void> _loadGenres() async {
    try {
      final json = await widget.api.getGenres(
        userId: widget.session.userId,
        types: widget.itemType,
      );
      if (!mounted) return;
      setState(
        () => _genres = usableGenres([
          for (final item in json) Genre.fromJson(item),
        ], type: widget.itemType),
      );
    } on JellyfinException {
      // Pas de genres pour l'instant : seulement « Trier »
    }
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
    final generation = _generation;
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
        sortBy: widget.showFilters ? _sort.sortBy : widget.sortBy,
        releasedBefore: widget.releasedBefore,
        personId: widget.personId,
        genreId: _genreId ?? widget.genreId,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (reset) {
          _items.clear();
          _shown.clear();
        }
        _items.addAll(page.items);
        _totalCount = page.totalCount;
        // Sécurité : le serveur n'a plus rien à donner
        if (page.items.isEmpty) _totalCount = _items.length;
      });
    } on JellyfinException catch (e) {
      if (generation != _generation) return;
      if (e.isUnauthorized) {
        // Jeton révoqué pendant l'utilisation : retour à la connexion
        widget.onUnauthorized();
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  /// Tirer vers le bas : on recharge depuis le début.
  Future<void> _refresh() => _loadMore(reset: true);

  /// Nouveau genre ou nouveau tri : la grille repart du début.
  void _restart() {
    _generation++;
    setState(() {
      _items.clear();
      _shown.clear();
      _totalCount = null;
      _error = null;
      _loading = false;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _loadMore(reset: true);
  }

  void _selectGenre(String? genreId) {
    if (genreId == _genreId) return;
    _genreId = genreId;
    _restart();
  }

  Future<void> _chooseSort() async {
    final chosen = await showPicker(
      context,
      title: 'Trier',
      options: [
        for (final sort in LibrarySort.values) PickerOption(sort, sort.label),
      ],
      selected: _sort,
    );
    if (chosen == null || chosen.value == _sort) return;
    _sort = chosen.value;
    await _preferences.saveSort(widget.itemType, _sort);
    _restart();
  }

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
    // Tablette : alignée sur le titre de l'onglet (téléphone inchangé)
    final side = _sideMargin(context);
    final padding = EdgeInsets.fromLTRB(side, 12, side, 12);

    final Widget content;
    if (_items.isEmpty && (_loading || _totalCount == null) && _error == null) {
      // Chargement : la grille a déjà sa forme, en zones grises
      content = SliverPadding(
        padding: padding,
        sliver: SliverGrid.builder(
          gridDelegate: _gridDelegate,
          itemCount: 12,
          itemBuilder: (_, _) => const _PosterTileSkeleton(),
        ),
      );
    } else if (_items.isEmpty && _error != null) {
      content = SliverFillRemaining(
        hasScrollBody: false,
        child: _MessageView(
          icon: Icons.cloud_off_rounded,
          message: _error!,
          onRetry: _refresh,
        ),
      );
    } else if (_items.isEmpty) {
      content = SliverFillRemaining(
        hasScrollBody: false,
        child: _MessageView(
          icon: Icons.movie_outlined,
          message: _genreId != null
              ? 'Rien dans ce genre pour l\'instant.'
              : widget.emptyMessage,
          onRetry: _refresh,
        ),
      );
    } else {
      content = SliverPadding(
        padding: padding,
        sliver: SliverGrid.builder(
          // Le nombre de colonnes s'adapte à la largeur de l'écran
          gridDelegate: _gridDelegate,
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            final tile = _PosterTile(
              api: widget.api,
              item: item,
              onTap: () => widget.onOpen(item),
              onLongPress: () => _showOptions(item),
            );
            // Nouvelle affiche : arrive en fondu (une fois seulement)
            if (!_shown.add(item.id)) return tile;
            return EntranceAnimation(
              delay: Duration(
                milliseconds: 25 * (index % _pageSize).clamp(0, 12),
              ),
              child: tile,
            );
          },
        ),
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
          SliverToBoxAdapter(child: SizedBox(height: widget.topPadding)),
          if (widget.showFilters)
            SliverToBoxAdapter(
              child: _FilterBar(
                genres: _genres,
                selected: _genreId,
                sort: _sort,
                onGenre: _selectGenre,
                onSort: _chooseSort,
              ),
            ),
          content,
          if (_items.isNotEmpty) SliverToBoxAdapter(child: _buildFooter()),
        ],
      ),
    );
  }

  /// Appui long sur une affiche : marquer comme vu / pas vu.
  Future<void> _showOptions(MediaItem item) async {
    final played = WatchedState.instance.of(item).played;
    final chosen = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                played ? Icons.remove_done_rounded : Icons.check_rounded,
              ),
              title: Text(played ? 'Marquer comme pas vu' : 'Marquer comme vu'),
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (chosen != true || !mounted) return;
    final userId = widget.session.userId;
    if (item.isSeries) {
      await setWatchedForAll(
        context,
        api: widget.api,
        userId: userId,
        itemId: item.id,
        what: 'toute la série',
        played: !played,
      );
    } else {
      await toggleWatched(
        context,
        api: widget.api,
        userId: userId,
        itemId: item.id,
        current: WatchedState.instance.of(item),
      );
    }
  }

  /// Marge de côté de la grille et des genres.
  static double _sideMargin(BuildContext context) =>
      AppLayout.isWide(context) ? AppLayout.gutter(context) : 16;

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

/// En haut de la grille : « Tous » et les genres en pastilles (qui
/// défilent), et le bouton « Trier ». Hors ligne : seulement « Trier ».
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.genres,
    required this.selected,
    required this.sort,
    required this.onGenre,
    required this.onSort,
  });

  final List<Genre>? genres;
  final String? selected;
  final LibrarySort sort;
  final ValueChanged<String?> onGenre;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final connection = ConnectionMonitor.instance;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: connection,
              builder: (context, _) {
                final genres = _visibleGenres(connection.online);
                return AnimatedSwitcher(
                  duration: AppDurations.medium,
                  child: genres == null
                      ? const SizedBox(height: 40)
                      : SizedBox(
                          height: 40,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.only(
                              left: _LibraryGridState._sideMargin(context),
                              right: 8,
                            ),
                            children: [
                              _chip('Tous', null),
                              for (final genre in genres)
                                _chip(genre.name, genre.id),
                            ],
                          ),
                        ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              right: _LibraryGridState._sideMargin(context),
            ),
            child: GlassCircleButton(
              icon: Icons.swap_vert_rounded,
              tooltip: 'Trier : ${sort.label}',
              size: 40,
              onPressed: onSort,
            ),
          ),
        ],
      ),
    );
  }

  /// Genres à montrer (null : rien, hors ligne ou pas encore chargés).
  List<Genre>? _visibleGenres(bool online) => online ? genres : null;

  Widget _chip(String label, String? genreId) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected == genreId,
      onSelected: (_) => onGenre(genreId),
    ),
  );
}

/// Une case de la grille : affiche (avec une ombre douce), titre et année.
/// S'enfonce un peu à l'appui.
class _PosterTile extends StatelessWidget {
  const _PosterTile({
    required this.api,
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  final JellyfinApi api;
  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return PressableScale(
      onTap: onTap,
      onLongPress: onLongPress,
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
                  // Vu (coche) ou épisodes pas vus (nombre), en haut à gauche
                  Positioned(top: 6, left: 6, child: WatchedBadge(item: item)),
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

/// Case en zones grises animées, pendant le chargement.
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

/// Message (bibliothèque vide, erreur) avec un bouton « Réessayer ».
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
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
