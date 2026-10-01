import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/media_item.dart';
import '../models/search_results.dart';
import '../models/session.dart';
import '../services/connection_monitor.dart';
import '../services/download_manager.dart';
import '../services/search_history.dart';
import '../theme/app_theme.dart';
import '../widgets/media_row.dart';
import '../widgets/ui.dart';
import 'movie_screen.dart';
import 'series_screen.dart';
import 'sorted_items_screen.dart';

/// Onglet Recherche : les résultats arrivent pendant la frappe (films,
/// séries, acteurs, épisodes). Avant de taper : les recherches récentes.
/// Hors ligne : recherche dans les téléchargements.
class SearchTab extends StatefulWidget {
  const SearchTab({
    super.key,
    required this.api,
    required this.session,
    required this.controller,
    required this.headerHeight,
    required this.bottomPadding,
    required this.active,
  });

  final JellyfinApi api;
  final Session session;
  final ScrollController controller;
  final double headerHeight;
  final double bottomPadding;

  /// Vrai quand l'onglet est affiché : le clavier s'ouvre.
  final bool active;

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  /// Pause de frappe avant de demander au serveur.
  static const _pause = Duration(milliseconds: 300);

  /// Lettres minimum pour chercher.
  static const _minLength = 2;

  final _text = TextEditingController();
  final _focus = FocusNode();
  final _history = SearchHistory();
  Timer? _debounce;

  List<String> _recent = const [];

  /// Recherche affichée, et ses résultats (null : pas encore arrivés).
  String _query = '';
  SearchResults? _results;
  bool _searching = false;

  /// Vrai si les résultats viennent des téléchargements (serveur absent).
  bool _offline = false;

  /// Numéro de la dernière recherche : une réponse plus ancienne, arrivée
  /// en retard, est ignorée.
  int _request = 0;

  String get _userId => widget.session.userId;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    if (widget.active) _openKeyboard();
  }

  @override
  void didUpdateWidget(SearchTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _openKeyboard();
    if (!widget.active && old.active) _focus.unfocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) _focus.requestFocus();
    });
  }

  Future<void> _loadHistory() async {
    final recent = await _history.load();
    if (mounted) setState(() => _recent = recent);
  }

  Future<void> _remember(String term) async {
    final recent = await _history.add(term);
    if (mounted) setState(() => _recent = recent);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final term = value.trim();
    if (term.length < _minLength) {
      _request++;
      setState(() {
        _query = term;
        _results = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(_pause, () => _search(term));
  }

  /// Relance une recherche récente.
  void _searchFor(String term) {
    _text.text = term;
    _text.selection = TextSelection.collapsed(offset: term.length);
    _debounce?.cancel();
    _search(term);
    _remember(term);
  }

  /// Fait une demande sans jamais échouer (null en cas d'erreur).
  Future<T?> _safe<T>(Future<T> request) async {
    try {
      return await request;
    } on JellyfinException {
      return null;
    }
  }

  Future<void> _search(String term) async {
    final request = ++_request;
    setState(() {
      _query = term;
      _searching = true;
    });

    SearchResults results;
    var offline = !ConnectionMonitor.instance.online;
    if (offline) {
      results = _searchDownloads(term);
    } else {
      final api = widget.api;
      final moviesFuture = _safe(
        api.searchItems(userId: _userId, term: term, type: 'Movie'),
      );
      final seriesFuture = _safe(
        api.searchItems(userId: _userId, term: term, type: 'Series'),
      );
      final episodesFuture = _safe(
        api.searchItems(userId: _userId, term: term, type: 'Episode'),
      );
      final peopleFuture = _safe(
        api.searchPersons(userId: _userId, term: term),
      );
      final movies = await moviesFuture;
      final series = await seriesFuture;
      final episodes = await episodesFuture;
      final people = await peopleFuture;
      if (movies == null && series == null && episodes == null) {
        // Serveur injoignable : dans les téléchargements
        offline = true;
        results = _searchDownloads(term);
      } else {
        results = SearchResults(
          movies: [
            for (final json in movies ?? const <Map<String, dynamic>>[])
              MediaItem.fromJson(json),
          ],
          series: [
            for (final json in series ?? const <Map<String, dynamic>>[])
              MediaItem.fromJson(json),
          ],
          episodes: [
            for (final json in episodes ?? const <Map<String, dynamic>>[])
              SearchEpisode.fromJson(json),
          ],
          people: [
            for (final json in people ?? const <Map<String, dynamic>>[])
              SearchPerson.fromJson(json),
          ],
        );
      }
    }
    // Une recherche plus récente est partie entre-temps
    if (!mounted || request != _request) return;
    setState(() {
      _results = results;
      _offline = offline;
      _searching = false;
    });
  }

  SearchResults _searchDownloads(String term) => searchDownloads([
    for (final state in DownloadManager.instance.states.values)
      if (state.phase == DownloadPhase.complete && state.info != null)
        state.info!,
  ], term);

  // ---------- Ouvrir un résultat ----------

  void _open(MediaItem item, {String? heroTag, String? seasonId}) {
    _remember(_query);
    _focus.unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => item.isSeries
            ? SeriesScreen(
                api: widget.api,
                session: widget.session,
                series: item,
                initialSeasonId: seasonId,
                heroTag: heroTag,
              )
            : MovieScreen(
                api: widget.api,
                session: widget.session,
                movie: item,
                heroTag: heroTag,
              ),
      ),
    );
  }

  /// Films et séries d'un acteur, du plus récent au plus ancien.
  void _openPerson(SearchPerson person) {
    _remember(_query);
    _focus.unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SortedItemsScreen(
          api: widget.api,
          session: widget.session,
          title: person.name,
          itemType: 'Movie,Series',
          sortBy: 'ProductionYear',
          personId: person.id,
        ),
      ),
    );
  }

  // ---------- Affichage ----------

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayout.of(context);
    final Widget body;
    final String key;
    if (_query.length < _minLength) {
      key = 'recent';
      body = _buildRecent(layout);
    } else if (_results == null) {
      key = 'loading';
      body = const Padding(
        padding: EdgeInsets.only(top: 18),
        child: Column(
          children: [
            MediaRowSkeleton(),
            SizedBox(height: 26),
            MediaRowSkeleton(),
          ],
        ),
      );
    } else if (_results!.isEmpty) {
      key = 'empty-$_query';
      body = _buildEmpty(layout);
    } else {
      key = 'results-$_query';
      body = _buildResults(layout, _results!);
    }

    return ListView(
      controller: widget.controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        top: widget.headerHeight + 8,
        bottom: widget.bottomPadding + 24,
      ),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.gutter),
          child: _SearchField(
            controller: _text,
            focusNode: _focus,
            searching: _searching,
            onChanged: _onChanged,
            onSubmitted: (value) {
              final term = value.trim();
              if (term.length >= _minLength) _remember(term);
            },
          ),
        ),
        if (_offline && _query.length >= _minLength)
          Padding(
            padding: EdgeInsets.fromLTRB(layout.gutter, 12, layout.gutter, 0),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 16,
                  color: AppColors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Hors ligne : recherche dans tes téléchargements',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        // Fondu d'un état à l'autre (récentes, chargement, résultats)
        AnimatedSwitcher(
          duration: AppDurations.medium,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          child: KeyedSubtree(key: ValueKey(key), child: body),
        ),
      ],
    );
  }

  Widget _buildRecent(HomeLayout layout) {
    final textTheme = Theme.of(context).textTheme;
    if (_recent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(36, 80, 36, 0),
        child: Text(
          'Cherche un film, une série, un épisode, un acteur ou un '
          'réalisateur.',
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge?.copyWith(color: AppColors.textSoft),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(layout.gutter, 22, layout.gutter - 8, 0),
      // Surface transparente : l'effet d'appui des lignes reste visible
      // par-dessus le fond dégradé
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recherches récentes',
                    style: textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final recent = await _history.clear();
                    if (mounted) setState(() => _recent = recent);
                  },
                  style: TextButton.styleFrom(foregroundColor: AppColors.grey),
                  child: const Text('Tout effacer'),
                ),
              ],
            ),
            for (final term in _recent)
              ListTile(
                key: ValueKey(term),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.history_rounded,
                  color: AppColors.grey,
                ),
                title: Text(term, style: textTheme.bodyLarge),
                onTap: () => _searchFor(term),
                trailing: IconButton(
                  tooltip: 'Retirer',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: AppColors.grey,
                  onPressed: () async {
                    final recent = await _history.remove(term);
                    if (mounted) setState(() => _recent = recent);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(HomeLayout layout) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 70, 36, 0),
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, size: 40, color: AppColors.grey),
          const SizedBox(height: 14),
          Text(
            'Aucun résultat pour « $_query »',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Vérifie l\'orthographe, ou essaie un seul mot du titre.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(HomeLayout layout, SearchResults results) {
    final sections = <Widget>[
      if (results.movies.isNotEmpty)
        MediaRow(
          title: 'Films',
          children: [
            for (final movie in results.movies)
              MediaTile(
                api: widget.api,
                item: movie,
                title: movie.name,
                subtitle: movie.year?.toString() ?? '',
                heroTag: 'search-${movie.id}',
                onTap: () => _open(movie, heroTag: 'search-${movie.id}'),
              ),
          ],
        ),
      if (results.series.isNotEmpty)
        MediaRow(
          title: 'Séries',
          children: [
            for (final series in results.series)
              MediaTile(
                api: widget.api,
                item: series,
                title: series.name,
                subtitle: series.year?.toString() ?? '',
                heroTag: 'search-${series.id}',
                onTap: () => _open(series, heroTag: 'search-${series.id}'),
              ),
          ],
        ),
      if (results.people.isNotEmpty)
        _PeopleRow(
          api: widget.api,
          people: results.people,
          onOpen: _openPerson,
        ),
      if (results.episodes.isNotEmpty)
        _EpisodeList(
          api: widget.api,
          episodes: results.episodes,
          onOpen: (episode) =>
              _open(episode.series, seasonId: episode.seasonId),
        ),
    ];
    return Column(
      children: [
        for (final (i, section) in sections.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            // Les sections arrivent l'une après l'autre
            child: EntranceAnimation(
              delay: Duration(milliseconds: 60 * i),
              child: section,
            ),
          ),
      ],
    );
  }
}

/// Champ de recherche en forme de pilule : loupe, texte, croix pour effacer
/// (ou petite roue pendant la recherche).
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.searching,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool searching;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    const pill = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
      borderSide: BorderSide(color: AppColors.glassBorder),
    );
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        autocorrect: false,
        decoration: InputDecoration(
          hintText: 'Films, séries, épisodes, acteurs…',
          prefixIcon: const Icon(Icons.search_rounded),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: pill,
          enabledBorder: pill,
          focusedBorder: pill.copyWith(
            borderSide: const BorderSide(color: AppColors.outlineStrong),
          ),
          suffixIcon: searching
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Effacer',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                    focusNode.requestFocus();
                  },
                ),
        ),
      ),
    );
  }
}

/// Acteurs et réalisateurs : photo ronde (ou initiales) et nom.
class _PeopleRow extends StatelessWidget {
  const _PeopleRow({
    required this.api,
    required this.people,
    required this.onOpen,
  });

  final JellyfinApi api;
  final List<SearchPerson> people;
  final ValueChanged<SearchPerson> onOpen;

  static const _size = 84.0;

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayout.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.gutter),
          child: Text(
            'Acteurs et réalisateurs',
            style: textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: _size + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: layout.gutter),
            itemCount: people.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final person = people[index];
              final url = api.imageUrl(
                itemId: person.id,
                type: 'Primary',
                tag: person.imageTag,
                width: 240,
              );
              final initials = Center(
                child: Text(
                  person.initials,
                  style: textTheme.titleLarge?.copyWith(color: AppColors.grey),
                ),
              );
              return PressableScale(
                onTap: () => onOpen(person),
                child: SizedBox(
                  width: _size,
                  child: Column(
                    children: [
                      ClipOval(
                        child: SizedBox.square(
                          dimension: _size,
                          child: ColoredBox(
                            color: AppColors.surface3,
                            child: url == null
                                ? initials
                                : CachedNetworkImage(
                                    imageUrl: url,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 240,
                                    placeholder: (_, _) => initials,
                                    errorWidget: (_, _, _) => initials,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        person.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Épisodes trouvés : vignette, série, « S5 · É1 · Titre ».
class _EpisodeList extends StatelessWidget {
  const _EpisodeList({
    required this.api,
    required this.episodes,
    required this.onOpen,
  });

  final JellyfinApi api;
  final List<SearchEpisode> episodes;
  final ValueChanged<SearchEpisode> onOpen;

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayout.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Épisodes',
            style: textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (final episode in episodes)
            PressableScale(
              onTap: () => onOpen(episode),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 128,
                      height: 72,
                      child: _EpisodeImage(api: api, episode: episode),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            episode.series.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            episode.detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: AppColors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.greyDark,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Vignette d'un épisode trouvé (fichier du téléphone s'il est téléchargé).
class _EpisodeImage extends StatelessWidget {
  const _EpisodeImage({required this.api, required this.episode});

  final JellyfinApi api;
  final SearchEpisode episode;

  @override
  Widget build(BuildContext context) {
    const icon = Center(
      child: Icon(Icons.tv_rounded, color: AppColors.greyDark),
    );
    final file = DownloadManager.instance.thumbFile(episode.id);
    final local = file == null
        ? icon
        : Image.file(
            file,
            fit: BoxFit.cover,
            cacheWidth: 480,
            errorBuilder: (_, _, _) => icon,
          );
    final url = api.imageUrl(
      itemId: episode.id,
      type: 'Primary',
      tag: episode.imageTag,
      width: 480,
    );
    return Card(
      child: url == null
          ? local
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              memCacheWidth: 480,
              placeholder: (_, _) => const SizedBox.shrink(),
              errorWidget: (_, _, _) => local,
            ),
    );
  }
}
