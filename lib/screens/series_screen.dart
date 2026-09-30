import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/episode.dart';
import '../models/item_details.dart';
import '../models/languages.dart';
import '../models/media_item.dart';
import '../models/media_track.dart';
import '../models/season.dart';
import '../models/session.dart';
import '../models/track_choice.dart';
import '../services/track_preferences.dart';
import '../widgets/details_page.dart';
import '../widgets/track_picker.dart';
import 'player_screen.dart';

/// Fiche d'une série : infos, résumé, choix de la saison, liste des épisodes.
class SeriesScreen extends StatefulWidget {
  const SeriesScreen({
    super.key,
    required this.api,
    required this.session,
    required this.series,
  });

  final JellyfinApi api;
  final Session session;
  final MediaItem series;

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

  // Langues choisies pour toute la série (retenues sur le téléphone)
  final _trackPreferences = TrackPreferences();
  LanguagePreference _languages = const LanguagePreference();

  String get _userId => widget.session.userId;

  @override
  void initState() {
    super.initState();
    _loadDetails();
    _loadSeasons();
    _loadLanguages();
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
        for (final language in languagesOf(_allTracks, TrackType.subtitle))
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
      final details = await widget.api.getItemDetails(
        userId: _userId,
        itemId: widget.series.id,
      );
      if (mounted) setState(() => _details = details);
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _detailsError = e.message);
    } finally {
      if (mounted) setState(() => _detailsLoading = false);
    }
  }

  Future<void> _loadSeasons() async {
    setState(() => _seasonsError = null);
    try {
      final seasons = await widget.api.getSeasons(
        userId: _userId,
        seriesId: widget.series.id,
      );
      if (!mounted) return;
      setState(() => _seasons = seasons);
      if (seasons.isNotEmpty) {
        // On ouvre la saison 1 plutôt que les « Spéciaux » (saison 0)
        await _selectSeason(
          seasons.firstWhere(
            (s) => (s.number ?? 1) >= 1,
            orElse: () => seasons.first,
          ),
        );
        // Puis on prépare les autres saisons, pour qu'elles s'ouvrent aussitôt
        _prefetchSeasons(seasons);
      }
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _seasonsError = e.message);
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

  Future<void> _play(Episode episode) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          api: widget.api,
          session: widget.session,
          itemId: episode.id,
          title: episode.playerTitle,
          // Les langues de la série, appliquées aux pistes de cet épisode
          tracks: _languages.resolve(episode.tracks),
        ),
      ),
    );
    // Au retour : met à jour les coches « déjà vu »
    final season = _selectedSeason;
    if (season != null && mounted) _loadEpisodes(season);
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final details = _details;

    return DetailsPage(
      api: widget.api,
      item: series,
      details: details,
      showBackdropFallback: !_detailsLoading,
      children: [
        DetailsHeader(
          api: widget.api,
          item: series,
          infos: [
            ?(details?.yearsLabel ?? series.year?.toString()),
            ?details?.statusLabel,
            ?details?.officialRating,
          ],
          rating: details?.ratingLabel,
        ),
        const SizedBox(height: 20),
        if (details != null)
          DetailsOverview(details: details)
        else if (_detailsError != null)
          RetryMessage(message: _detailsError!, onRetry: _loadDetails)
        else
          const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 16),
        Text(
          'Langues pour toute la série',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        TrackSelectorTile(
          icon: Icons.audiotrack,
          title: 'Audio',
          value: _languages.audioLabel,
          onTap: _chooseAudioLanguage,
        ),
        TrackSelectorTile(
          icon: Icons.subtitles,
          title: 'Sous-titres',
          value: _languages.subtitleLabel,
          onTap: _chooseSubtitleLanguage,
        ),
        const SizedBox(height: 16),
        ..._buildSeasons(),
      ],
    );
  }

  /// Rangée de choix de la saison, puis les épisodes de la saison choisie.
  List<Widget> _buildSeasons() {
    final seasons = _seasons;
    if (seasons == null) {
      return [
        if (_seasonsError != null)
          RetryMessage(message: _seasonsError!, onRetry: _loadSeasons)
        else
          const Center(child: CircularProgressIndicator()),
      ];
    }
    if (seasons.isEmpty) {
      return [const Text('Aucune saison pour cette série.')];
    }

    final selected = _selectedSeason;
    final shownId = _shownSeasonId;
    final episodes = shownId == null ? null : _episodes[shownId];
    // La saison choisie charge encore (l'ancienne liste reste affichée)
    final switching =
        selected != null &&
        shownId != selected.id &&
        _loadingSeasons.contains(selected.id);

    return [
      // Défilement horizontal si les saisons ne tiennent pas en largeur
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final season in seasons)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(season.name),
                  selected: season.id == selected?.id,
                  onSelected: (_) => _selectSeason(season),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      // Fine barre de chargement, sans changer la hauteur de la page
      SizedBox(
        height: 4,
        child: switching && episodes != null
            ? const LinearProgressIndicator()
            : null,
      ),
      const SizedBox(height: 8),
      if (_episodesError != null && selected != null)
        RetryMessage(
          message: _episodesError!,
          onRetry: () => _selectSeason(selected),
        )
      else if (episodes == null)
        const Center(child: CircularProgressIndicator())
      else if (episodes.isEmpty)
        const Text('Aucun épisode dans cette saison.')
      else
        for (final episode in episodes)
          _EpisodeTile(
            api: widget.api,
            episode: episode,
            onTap: () => _play(episode),
          ),
    ];
  }
}

/// Une ligne de la liste : vignette (avec coche si déjà vu), numéro et titre,
/// durée, début du résumé. Un appui lance la lecture.
class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.api,
    required this.episode,
    required this.onTap,
  });

  /// Largeur demandée au serveur pour la vignette, en pixels.
  static const _imageWidth = 400;

  final JellyfinApi api;
  final Episode episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final url = api.episodeImageUrl(episode, width: _imageWidth);
    final overview = episode.overview?.trim() ?? '';
    final placeholder = Center(
      child: Icon(Icons.tv, color: colors.onSurfaceVariant),
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Card(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (url == null)
                        placeholder
                      else
                        CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          memCacheWidth: _imageWidth,
                          placeholder: (_, _) => const SizedBox.shrink(),
                          errorWidget: (_, _, _) => placeholder,
                        ),
                      // Déjà vu : petite coche en haut à droite
                      if (episode.played)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: CircleAvatar(
                            radius: 11,
                            backgroundColor: colors.primary,
                            child: Icon(
                              Icons.check,
                              size: 14,
                              color: colors.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.listTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall,
                  ),
                  if (episode.infoLine.isNotEmpty)
                    Text(
                      episode.infoLine,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  if (overview.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      overview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
