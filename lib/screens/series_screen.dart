import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/download_info.dart';
import '../models/episode.dart';
import '../models/item_details.dart';
import '../models/languages.dart';
import '../models/media_item.dart';
import '../models/media_track.dart';
import '../models/season.dart';
import '../models/session.dart';
import '../models/track_choice.dart';
import '../services/connection_monitor.dart';
import '../services/device_capabilities.dart';
import '../services/download_groups.dart';
import '../services/download_manager.dart';
import '../services/offline_progress.dart';
import '../services/playback_launcher.dart';
import '../services/track_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/details_page.dart';
import '../widgets/download_controls.dart';
import '../widgets/track_picker.dart';
import '../widgets/ui.dart';
import '../widgets/watched_controls.dart';
import '../widgets/tv_focus.dart';

/// Fiche d'une série : infos, résumé, choix de la saison, liste des épisodes.
/// Sans serveur, si des épisodes sont téléchargés : la même fiche, avec
/// seulement ces épisodes (et leurs saisons).
class SeriesScreen extends StatefulWidget {
  const SeriesScreen({
    super.key,
    required this.api,
    required this.session,
    required this.series,
    this.initialSeasonId,
    this.heroTag,
  });

  final JellyfinApi api;
  final Session session;
  final MediaItem series;

  /// Saison à ouvrir (ex. celle de l'épisode en cours). Null : la saison 1.
  final String? initialSeasonId;

  /// Nom de l'animation de l'affiche (celui de la grille par défaut).
  final String? heroTag;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  // Fiche de la série
  ItemDetails? _details;
  bool _detailsLoading = false;
  String? _detailsError;

  // Saisons
  List<Season>? _seasons;
  String? _seasonsError;
  Season? _selectedSeason;

  // Épisodes, gardés en mémoire par saison (identifiant de saison → épisodes)
  final Map<String, List<Episode>> _episodes = {};

  /// Saisons en cours de chargement.
  final Set<String> _loadingSeasons = {};

  /// Saison dont les épisodes sont affichés. Pendant le chargement d'une
  /// nouvelle saison, l'ancienne liste reste affichée : la page ne saute pas.
  String? _shownSeasonId;
  String? _episodesError;

  /// Pastille de la saison choisie (pour la faire défiler jusqu'à l'écran).
  final _selectedChipKey = GlobalKey();

  // Langues choisies pour toute la série (retenues sur le téléphone)
  final _trackPreferences = TrackPreferences();
  LanguagePreference _languages = const LanguagePreference();

  /// Vrai quand la fiche vient des épisodes téléchargés (pas de serveur).
  bool _offline = false;

  String get _userId => widget.session.userId;

  @override
  void initState() {
    super.initState();
    _loadLanguages();
    // Déjà hors ligne : directement les épisodes téléchargés
    if (!ConnectionMonitor.instance.online && _downloaded().isNotEmpty) {
      _showOffline();
    } else {
      _loadDetails();
      _loadSeasons();
    }
    DownloadManager.instance.addListener(_onDownloadsChanged);
  }

  @override
  void dispose() {
    DownloadManager.instance.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  /// Épisodes de la série entièrement téléchargés.
  List<DownloadInfo> _downloaded() => [
    for (final state in DownloadManager.instance.states.values)
      if (state.phase == DownloadPhase.complete &&
          state.info?.seriesId == widget.series.id)
        state.info!,
  ];

  /// Attente courte du serveur quand on peut se passer de lui.
  Future<T> _request<T>(Future<T> request) => _downloaded().isEmpty
      ? request
      : request.timeout(const Duration(seconds: 5));

  /// Remplit la fiche avec les épisodes téléchargés (serveur injoignable).
  /// Faux s'il n'y en a pas.
  bool _showOffline() {
    final downloaded = _downloaded();
    if (downloaded.isEmpty || !mounted) return false;
    final offline = OfflineSeries.of(
      downloaded,
      progressOf: (id) => OfflineProgress.instance.of(id)?.toWatchProgress(),
    );
    setState(() {
      _offline = true;
      _details = offline.details;
      _detailsError = null;
      _seasons = offline.seasons;
      _seasonsError = null;
      _episodesError = null;
      _loadingSeasons.clear();
      _episodes
        ..clear()
        ..addAll(offline.episodes);
      final wanted = _selectedSeason?.id ?? widget.initialSeasonId;
      final season =
          offline.seasons.where((s) => s.id == wanted).firstOrNull ??
          offline.seasons.first;
      _selectedSeason = season;
      _shownSeasonId = season.id;
    });
    return true;
  }

  /// Hors ligne, un épisode supprimé disparaît de la fiche (et la fiche se
  /// ferme s'il n'en reste plus).
  void _onDownloadsChanged() {
    if (!_offline || !mounted) return;
    if (_downloaded().isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    final shown = _episodes.values.fold(0, (sum, list) => sum + list.length);
    if (shown != _downloaded().length) _showOffline();
  }

  Future<void> _loadLanguages() async {
    final languages = await _trackPreferences.load(widget.series.id);
    if (mounted) setState(() => _languages = languages);
  }

  Future<void> _saveLanguages(LanguagePreference languages) async {
    setState(() => _languages = languages);
    await _trackPreferences.save(widget.series.id, languages);
  }

  /// Toutes les pistes des épisodes déjà chargés (pour lister les langues).
  Iterable<MediaTrack> get _allTracks =>
      _episodes.values.expand((episodes) => episodes).expand((e) => e.tracks);

  Future<void> _chooseAudioLanguage() async {
    final chosen = await showPicker(
      context,
      title: 'Audio pour toute la série',
      options: [
        const PickerOption<String?>(
          null,
          'Par défaut',
          description: 'Selon les réglages de ton compte Jellyfin',
        ),
        for (final language in languagesOf(_allTracks, TrackType.audio))
          PickerOption<String?>(language, languageName(language)),
      ],
      selected: _languages.audioLanguage,
    );
    if (chosen == null) return;
    await _saveLanguages(
      LanguagePreference(
        audioLanguage: chosen.value,
        subtitleLanguage: _languages.subtitleLanguage,
      ),
    );
  }

  Future<void> _chooseSubtitleLanguage() async {
    final chosen = await showPicker(
      context,
      title: 'Sous-titres pour toute la série',
      options: [
        const PickerOption<String?>(
          null,
          'Par défaut',
          description: 'Selon les réglages de ton compte Jellyfin',
        ),
        const PickerOption<String?>(LanguagePreference.noSubtitles, 'Aucun'),
        // Seulement les langues avec des sous-titres affichables (pas PGS)
        for (final language in languagesOf(
          _allTracks.where(DeviceCapabilities.playerCodecs.showsSubtitle),
          TrackType.subtitle,
        ))
          PickerOption<String?>(language, languageName(language)),
      ],
      selected: _languages.subtitleLanguage,
    );
    if (chosen == null) return;
    await _saveLanguages(
      LanguagePreference(
        audioLanguage: _languages.audioLanguage,
        subtitleLanguage: chosen.value,
      ),
    );
  }

  Future<void> _loadDetails() async {
    setState(() {
      _detailsLoading = true;
      _detailsError = null;
    });
    try {
      final details = await _request(
        widget.api.getItemDetails(userId: _userId, itemId: widget.series.id),
      );
      if (mounted && !_offline) setState(() => _details = details);
    } on Exception catch (e) {
      if (_showOffline()) return;
      if (mounted) {
        setState(
          () => _detailsError = e is JellyfinException
              ? e.message
              : 'Le serveur ne répond pas.',
        );
      }
    } finally {
      if (mounted) setState(() => _detailsLoading = false);
    }
  }

  Future<void> _loadSeasons() async {
    setState(() => _seasonsError = null);
    try {
      final seasons = await _request(
        widget.api.getSeasons(userId: _userId, seriesId: widget.series.id),
      );
      if (!mounted || _offline) return;
      setState(() => _seasons = seasons);
      if (seasons.isNotEmpty) {
        // La saison demandée, sinon la saison 1 plutôt que les « Spéciaux »
        // (saison 0)
        final initial =
            seasons.where((s) => s.id == widget.initialSeasonId).firstOrNull ??
            seasons.firstWhere(
              (s) => (s.number ?? 1) >= 1,
              orElse: () => seasons.first,
            );
        // Pastille de la saison bien visible, même loin à droite (seule la
        // rangée des saisons défile, pas la page)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final chip = _selectedChipKey.currentContext;
          final box = chip?.findRenderObject();
          if (chip == null || !chip.mounted || box == null) return;
          Scrollable.of(chip).position.ensureVisible(
            box,
            alignment: 0.5,
            duration: AppDurations.medium,
          );
        });
        await _selectSeason(initial);
        // Puis on prépare les autres saisons, pour qu'elles s'ouvrent aussitôt
        _prefetchSeasons(seasons);
      }
    } on Exception catch (e) {
      if (_showOffline()) return;
      if (mounted) {
        setState(
          () => _seasonsError = e is JellyfinException
              ? e.message
              : 'Le serveur ne répond pas.',
        );
      }
    }
  }

  Future<void> _selectSeason(Season season) async {
    setState(() {
      _selectedSeason = season;
      _episodesError = null;
      // Déjà en mémoire : affichage immédiat
      if (_episodes.containsKey(season.id)) _shownSeasonId = season.id;
    });
    if (!_episodes.containsKey(season.id) &&
        !_loadingSeasons.contains(season.id)) {
      await _loadEpisodes(season);
    }
  }

  /// Charge les épisodes d'une saison et les garde en mémoire.
  Future<void> _loadEpisodes(Season season) async {
    setState(() => _loadingSeasons.add(season.id));
    try {
      final episodes = await widget.api.getEpisodes(
        userId: _userId,
        seriesId: widget.series.id,
        seasonId: season.id,
      );
      if (!mounted) return;
      setState(() {
        _episodes[season.id] = episodes;
        if (_selectedSeason?.id == season.id) _shownSeasonId = season.id;
      });
    } on JellyfinException catch (e) {
      // L'erreur n'est affichée que pour la saison choisie
      if (mounted && _selectedSeason?.id == season.id) {
        setState(() => _episodesError = e.message);
      }
    } finally {
      if (mounted) setState(() => _loadingSeasons.remove(season.id));
    }
  }

  /// Charge en arrière-plan, une par une, les saisons pas encore chargées.
  Future<void> _prefetchSeasons(List<Season> seasons) async {
    for (final season in seasons) {
      if (!mounted) return;
      if (_episodes.containsKey(season.id) ||
          _loadingSeasons.contains(season.id)) {
        continue;
      }
      await _loadEpisodes(season);
    }
  }

  /// Vérifie avec le serveur si la lecture directe est possible (fenêtre
  /// d'explication sinon), puis ouvre le lecteur. Un épisode commencé
  /// reprend là où il s'était arrêté, sauf [start] précisé.
  Future<void> _play(Episode episode, {Duration? start}) async {
    final progress = episode.progress;
    final lastId = await launchPlayback(
      context,
      api: widget.api,
      session: widget.session,
      itemId: episode.id,
      title: episode.playerTitle,
      subtitle: episode.playerSubtitle,
      // Les langues de la série, appliquées aux pistes de cet épisode
      tracks: _languages.resolve(
        episode.tracks,
        player: DeviceCapabilities.playerCodecs,
      ),
      start: start ?? (progress.canResume ? progress.position : Duration.zero),
    );
    if (!mounted) return;
    // Épisodes enchaînés jusqu'à une autre saison : on y va
    final lastSeason = lastId == null || lastId == episode.id
        ? null
        : _seasonOf(lastId);
    // Au retour : met à jour les coches « déjà vu » et les progressions
    if (_offline) {
      if (lastSeason != null) _selectedSeason = lastSeason;
      _showOffline();
      return;
    }
    final season = lastSeason ?? _selectedSeason;
    if (season == null) return;
    if (season.id != _selectedSeason?.id) await _selectSeason(season);
    if (mounted) _loadEpisodes(season);
  }

  /// Saison (déjà chargée) qui contient l'épisode [episodeId].
  Season? _seasonOf(String episodeId) {
    final seasonId = _episodes.entries
        .where((entry) => entry.value.any((e) => e.id == episodeId))
        .firstOrNull
        ?.key;
    return _seasons?.where((s) => s.id == seasonId).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final details = _details;
    final Widget overview;
    if (details != null) {
      overview = DetailsOverview(details: details);
    } else if (_detailsError != null) {
      overview = RetryMessage(message: _detailsError!, onRetry: _loadDetails);
    } else {
      overview = const DetailsOverviewSkeleton();
    }
    // iPad en paysage : langues à gauche, résumé à droite, puis les saisons
    // et les épisodes sur toute la largeur
    final twoColumns = AppLayout.isTwoColumn(context);

    return DetailsPage(
      api: widget.api,
      item: series,
      details: details,
      showBackdropFallback: !_detailsLoading,
      header: DetailsHeader(
        api: widget.api,
        item: series,
        infos: [
          ?(details?.yearsLabel ?? series.year?.toString()),
          ?details?.statusLabel,
          ?details?.officialRating,
        ],
        rating: details?.ratingLabel,
        heroTag: widget.heroTag,
      ),
      aside: twoColumns ? [overview] : const [],
      below: twoColumns ? _buildSeasons(twoColumns: true) : const [],
      children: [
        if (!twoColumns) ...[overview, const SizedBox(height: 26)],
        Text(
          'Langues pour toute la série',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: AppColors.grey),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: GlassPanel(
                child: TrackSelectorTile(
                  icon: Icons.volume_up_outlined,
                  title: 'Audio',
                  value: _languages.audioLabel,
                  onTap: _chooseAudioLanguage,
                  showChevron: false,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlassPanel(
                child: TrackSelectorTile(
                  icon: Icons.subtitles_outlined,
                  title: 'Sous-titres',
                  value: _languages.subtitleLabel,
                  onTap: _chooseSubtitleLanguage,
                  showChevron: false,
                ),
              ),
            ),
          ],
        ),
        if (!twoColumns) ...[
          const SizedBox(height: 26),
          ..._buildSeasons(twoColumns: false),
        ],
      ],
    );
  }

  /// Rangée de choix de la saison, puis les épisodes de la saison choisie
  /// ([twoColumns] : deux épisodes par ligne).
  List<Widget> _buildSeasons({required bool twoColumns}) {
    final seasons = _seasons;
    if (seasons == null) {
      return [
        if (_seasonsError != null)
          RetryMessage(message: _seasonsError!, onRetry: _loadSeasons)
        else
          const _EpisodesSkeleton(),
      ];
    }
    if (seasons.isEmpty) {
      return [const Text('Aucune saison pour cette série.')];
    }

    final selected = _selectedSeason;
    final shownId = _shownSeasonId;
    final episodes = shownId == null ? null : _episodes[shownId];
    final shownSeason = seasons.where((s) => s.id == shownId).firstOrNull;
    // La saison choisie charge encore (l'ancienne liste reste affichée)
    final switching =
        selected != null &&
        shownId != selected.id &&
        _loadingSeasons.contains(selected.id);

    // Saisons en pilules, défilement horizontal si elles ne tiennent pas
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final season in seasons)
            Padding(
              key: season.id == selected?.id ? _selectedChipKey : null,
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                // Télé : la saison affichée est sélectionnée à l'arrivée
                autofocus: DeviceCapabilities.isTv && season.id == selected?.id,
                label: Text(season.name),
                selected: season.id == selected?.id,
                onSelected: (_) => _selectSeason(season),
              ),
            ),
        ],
      ),
    );
    // Télécharger toute la saison affichée
    final download =
        !_offline &&
            episodes != null &&
            episodes.isNotEmpty &&
            shownSeason != null
        ? SeasonDownloadButton(
            key: ValueKey(shownSeason.id),
            api: widget.api,
            userId: _userId,
            seasonName: shownSeason.name,
            episodes: episodes,
          )
        : null;

    // Saisons et bouton ⋯ (vu / pas vu), sauf hors ligne
    final seasonRow = _offline
        ? chips
        : Row(
            children: [
              Expanded(child: chips),
              const SizedBox(width: 8),
              GlassCircleButton(
                icon: Icons.more_horiz_rounded,
                tooltip: 'Marquer comme vu',
                size: 40,
                onPressed: () => _showWatchedMenu(shownSeason, episodes),
              ),
            ],
          );

    return [
      // Deux colonnes : le téléchargement de la saison à droite des saisons
      if (twoColumns)
        Row(
          children: [
            Expanded(flex: 6, child: seasonRow),
            const SizedBox(width: 40),
            Expanded(
              flex: 5,
              child: Align(
                alignment: Alignment.centerLeft,
                child: download ?? const SizedBox.shrink(),
              ),
            ),
          ],
        )
      else
        seasonRow,
      // Hors ligne : on précise ce qui est affiché
      if (_offline) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 16,
              color: AppColors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Hors ligne : seuls les épisodes téléchargés sont affichés.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ] else if (download != null && !twoColumns) ...[
        const SizedBox(height: 12),
        download,
      ],
      const SizedBox(height: 10),
      // Fine barre de chargement, sans changer la hauteur de la page
      SizedBox(
        height: 3,
        child: switching && episodes != null
            ? const LinearProgressIndicator(
                borderRadius: BorderRadius.all(Radius.circular(2)),
              )
            : null,
      ),
      const SizedBox(height: 8),
      if (_episodesError != null && selected != null)
        RetryMessage(
          message: _episodesError!,
          onRetry: () => _selectSeason(selected),
        )
      else if (episodes == null)
        const _EpisodesSkeleton()
      else if (episodes.isEmpty)
        const Text('Aucun épisode dans cette saison.')
      else if (twoColumns)
        for (var i = 0; i < episodes.length; i += 2)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _episodeTile(episodes[i])),
              const SizedBox(width: 24),
              Expanded(
                child: i + 1 < episodes.length
                    ? _episodeTile(episodes[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          )
      else
        for (final episode in episodes) _episodeTile(episode),
    ];
  }

  Widget _episodeTile(Episode episode) => _EpisodeTile(
    api: widget.api,
    userId: _userId,
    episode: episode,
    onTap: () => _play(episode),
    onLongPress: () => _toggleEpisodeWatched(episode),
    onInfo: () => _showEpisodeInfo(episode),
  );

  /// Marque un épisode comme vu / pas vu (avec « Annuler »).
  Future<void> _toggleEpisodeWatched(Episode episode) => toggleWatched(
    context,
    api: widget.api,
    userId: _userId,
    itemId: episode.id,
    current: episode.progress,
    related: [widget.series.id],
    onChanged: _afterWatchedChange,
  );

  /// Bouton ⋯ des saisons : marquer la saison affichée, ou toute la série,
  /// comme vue / pas vue.
  Future<void> _showWatchedMenu(Season? season, List<Episode>? episodes) async {
    final seasonPlayed =
        episodes != null &&
        episodes.isNotEmpty &&
        episodes.every((e) => e.played);
    final seriesPlayed = _details?.progress.played ?? false;
    final choice = await showModalBottomSheet<_WatchedTarget>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (season != null && episodes != null && episodes.isNotEmpty)
              ListTile(
                leading: Icon(
                  seasonPlayed
                      ? Icons.remove_done_rounded
                      : Icons.check_rounded,
                ),
                title: Text(
                  seasonPlayed
                      ? 'Marquer « ${season.name} » comme pas vue'
                      : 'Marquer « ${season.name} » comme vue',
                ),
                onTap: () => Navigator.of(context).pop(_WatchedTarget.season),
              ),
            ListTile(
              leading: Icon(
                seriesPlayed
                    ? Icons.remove_done_rounded
                    : Icons.done_all_rounded,
              ),
              title: Text(
                seriesPlayed
                    ? 'Marquer toute la série comme pas vue'
                    : 'Marquer toute la série comme vue',
              ),
              onTap: () => Navigator.of(context).pop(_WatchedTarget.series),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final forSeason = choice == _WatchedTarget.season && season != null;
    final changed = await setWatchedForAll(
      context,
      api: widget.api,
      userId: _userId,
      itemId: forSeason ? season.id : widget.series.id,
      what: forSeason ? '« ${season.name} »' : 'toute la série',
      played: forSeason ? !seasonPlayed : !seriesPlayed,
      related: forSeason ? [widget.series.id] : const [],
    );
    if (changed) await _afterWatchedChange(allSeasons: !forSeason);
  }

  /// Après un changement « vu » : relit la fiche (série toute vue ou pas) et
  /// la saison affichée. [allSeasons] : les autres saisons en mémoire sont
  /// oubliées, elles seront relues quand on les choisira.
  Future<void> _afterWatchedChange({bool allSeasons = false}) async {
    if (!mounted) return;
    final shownId = _shownSeasonId;
    if (allSeasons) _episodes.removeWhere((id, _) => id != shownId);
    final shown = _seasons?.where((s) => s.id == shownId).firstOrNull;
    await Future.wait([
      _loadDetails(),
      if (shown != null) _loadEpisodes(shown),
    ]);
  }

  /// Bouton ⓘ : infos de l'épisode dans un panneau qui monte du bas.
  /// Le panneau renvoie la position de départ choisie (null : fermé).
  Future<void> _showEpisodeInfo(Episode episode) async {
    final choice = await showModalBottomSheet<_EpisodeChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EpisodeSheet(api: widget.api, episode: episode),
    );
    if (choice == null || !mounted) return;
    if (choice.toggleWatched) {
      await _toggleEpisodeWatched(episode);
    } else {
      await _play(episode, start: choice.start);
    }
  }
}

/// Choix du bouton ⋯ des saisons.
enum _WatchedTarget { season, series }

/// Choix fait dans le panneau d'un épisode : le lire (à [start]), ou le
/// marquer comme vu / pas vu.
class _EpisodeChoice {
  const _EpisodeChoice.play(Duration this.start) : toggleWatched = false;
  const _EpisodeChoice.toggleWatched() : start = null, toggleWatched = true;

  final Duration? start;
  final bool toggleWatched;
}

/// Largeur demandée au serveur pour les vignettes d'épisode, en pixels.
const _episodeImageWidth = 480;

/// Vignette d'un épisode (image, ou icône s'il n'y en a pas).
class _EpisodeThumbnail extends StatelessWidget {
  const _EpisodeThumbnail({required this.api, required this.episode});

  final JellyfinApi api;
  final Episode episode;

  @override
  Widget build(BuildContext context) {
    final url = api.episodeImageUrl(episode, width: _episodeImageWidth);
    const icon = Center(
      child: Icon(Icons.tv_rounded, color: AppColors.greyDark),
    );
    // Hors ligne : la vignette téléchargée avec l'épisode, s'il y en a une
    final file = DownloadManager.instance.thumbFile(episode.id);
    final placeholder = file == null
        ? icon
        : Image.file(
            file,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: _episodeImageWidth,
            errorBuilder: (_, _, _) => icon,
          );
    return Card(
      child: url == null
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              memCacheWidth: _episodeImageWidth,
              fadeInDuration: AppDurations.fast,
              placeholder: (_, _) => const SizedBox.shrink(),
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}

/// Une ligne de la liste : vignette (avec coche si déjà vu), numéro et titre,
/// durée et qualité, bouton ⓘ. Un appui sur la ligne lance la lecture.
class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.api,
    required this.userId,
    required this.episode,
    required this.onTap,
    required this.onLongPress,
    required this.onInfo,
  });

  final JellyfinApi api;
  final String userId;
  final Episode episode;
  final VoidCallback onTap;

  /// Appui long : vu / pas vu.
  final VoidCallback onLongPress;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // Télé : ligne sélectionnable (OK = lecture, Menu = vu / pas vu)
    return TvFocusable(
      onTap: onTap,
      onMenu: onLongPress,
      scale: 1.02,
      child: _buildRow(context, textTheme),
    );
  }

  Widget _buildRow(BuildContext context, TextTheme textTheme) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      canRequestFocus: !DeviceCapabilities.isTv,
      borderRadius: BorderRadius.circular(AppRadius.poster),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 138,
              height: 78,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _EpisodeThumbnail(api: api, episode: episode),
                  // Commencé : fine barre de progression en bas de l'image
                  if (episode.progress.canResume && !episode.played)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(AppRadius.poster),
                        ),
                        child: ProgressLine(value: episode.progress.fraction),
                      ),
                    ),
                  // Déjà vu : petite coche blanche en haut à droite
                  if (episode.played)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: AppColors.white,
                        child: Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: AppColors.black,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.listTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall,
                  ),
                  // Infos habituelles, ou l'état du téléchargement
                  ListenableBuilder(
                    listenable: DownloadManager.instance,
                    builder: (context, _) {
                      final status = downloadStatusLabel(
                        DownloadManager.instance.stateOf(episode.id),
                      );
                      final line =
                          status ?? joinInfos(episode.infoLine.split(' · '));
                      if (line.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          line,
                          maxLines: 2,
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.grey,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            EpisodeDownloadButton(api: api, userId: userId, itemId: episode.id),
            const SizedBox(width: 8),
            GlassCircleButton(
              icon: Icons.info_outline_rounded,
              tooltip: 'Infos de l\'épisode',
              size: 40,
              onPressed: onInfo,
            ),
          ],
        ),
      ),
    );
  }
}

/// Panneau d'infos d'un épisode : image, titre, infos, résumé, et boutons de
/// lecture (« Lire l'épisode », ou « Reprendre à … » et « Depuis le début »).
/// Ferme le panneau en renvoyant la position de départ choisie.
class _EpisodeSheet extends StatelessWidget {
  const _EpisodeSheet({required this.api, required this.episode});

  final JellyfinApi api;
  final Episode episode;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final overview = episode.overview?.trim() ?? '';
    final progress = episode.progress;
    final season = episode.seasonNumber;
    final number = episode.number;

    return SafeArea(
      child: ConstrainedBox(
        // Pas plus de 85 % de l'écran : le résumé défile s'il est long
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _EpisodeThumbnail(api: api, episode: episode),
                ),
              ),
              const SizedBox(height: 18),
              if (season != null && number != null)
                Text(
                  'Saison $season · Épisode $number',
                  style: textTheme.labelLarge?.copyWith(color: AppColors.grey),
                ),
              const SizedBox(height: 6),
              Text(episode.name, style: textTheme.headlineSmall),
              if (episode.infoLine.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  joinInfos(episode.infoLine.split(' · ')),
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.grey),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                overview.isEmpty ? 'Pas de résumé disponible.' : overview,
                style: textTheme.bodyLarge?.copyWith(
                  color: overview.isEmpty ? AppColors.grey : AppColors.textSoft,
                ),
              ),
              const SizedBox(height: 22),
              if (progress.canResume && !episode.played) ...[
                ProgressLine(
                  value: progress.fraction,
                  height: 4,
                  rounded: true,
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context)
                          .pop(_EpisodeChoice.play(progress.position)),
                  icon: const Icon(Icons.play_arrow_rounded, size: 24),
                  label: Text(progress.resumeLabel),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context)
                          .pop(const _EpisodeChoice.play(Duration.zero)),
                  icon: const Icon(Icons.replay_rounded, size: 22),
                  label: const Text('Depuis le début'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context)
                          .pop(const _EpisodeChoice.play(Duration.zero)),
                  icon: const Icon(Icons.play_arrow_rounded, size: 24),
                  label: const Text('Lire l\'épisode'),
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context)
                        .pop(const _EpisodeChoice.toggleWatched()),
                icon: Icon(
                  episode.played
                      ? Icons.remove_done_rounded
                      : Icons.check_rounded,
                  size: 22,
                ),
                label: Text(
                  episode.played ? 'Marquer comme pas vu' : 'Marquer comme vu',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zones grises animées à la place des épisodes, pendant le chargement.
class _EpisodesSkeleton extends StatelessWidget {
  const _EpisodesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                SkeletonBox(width: 138, height: 78),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(height: 14, radius: 6),
                      SizedBox(height: 8),
                      SkeletonBox(width: 120, height: 12, radius: 6),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
