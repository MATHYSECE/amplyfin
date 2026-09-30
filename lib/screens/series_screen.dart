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
import '../services/playback_launcher.dart';
import '../services/track_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/details_page.dart';
import '../widgets/track_picker.dart';
import '../widgets/ui.dart';

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

  /// Vérifie avec le serveur si la lecture directe est possible (fenêtre
  /// d'explication sinon), puis ouvre le lecteur.
  Future<void> _play(Episode episode) async {
    await launchPlayback(
      context,
      api: widget.api,
      session: widget.session,
      itemId: episode.id,
      title: episode.playerTitle,
      subtitle: episode.playerSubtitle,
      // Les langues de la série, appliquées aux pistes de cet épisode
      tracks: _languages.resolve(episode.tracks),
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
      header: DetailsHeader(
        api: widget.api,
        item: series,
        infos: [
          ?(details?.yearsLabel ?? series.year?.toString()),
          ?details?.statusLabel,
          ?details?.officialRating,
        ],
        rating: details?.ratingLabel,
      ),
      children: [
        if (details != null)
          DetailsOverview(details: details)
        else if (_detailsError != null)
          RetryMessage(message: _detailsError!, onRetry: _loadDetails)
        else
          const DetailsOverviewSkeleton(),
        const SizedBox(height: 26),
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
        const SizedBox(height: 26),
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
          const _EpisodesSkeleton(),
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
      // Saisons en pilules, défilement horizontal si elles ne tiennent pas
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
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
      else
        for (final episode in episodes)
          _EpisodeTile(
            api: widget.api,
            episode: episode,
            onTap: () => _play(episode),
            onInfo: () => _showEpisodeInfo(episode),
          ),
    ];
  }

  /// Bouton ⓘ : infos de l'épisode dans un panneau qui monte du bas.
  Future<void> _showEpisodeInfo(Episode episode) async {
    final play = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EpisodeSheet(api: widget.api, episode: episode),
    );
    if (play == true && mounted) await _play(episode);
  }
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
    const placeholder = Center(
      child: Icon(Icons.tv_rounded, color: AppColors.greyDark),
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
    required this.episode,
    required this.onTap,
    required this.onInfo,
  });

  final JellyfinApi api;
  final Episode episode;
  final VoidCallback onTap;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
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
                  if (episode.infoLine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      joinInfos(episode.infoLine.split(' · ')),
                      maxLines: 2,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.grey,
                      ),
                    ),
                  ],
                ],
              ),
            ),
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

/// Panneau d'infos d'un épisode : image, titre, infos, résumé, et bouton
/// « Lire l'épisode » (ferme le panneau en renvoyant true).
class _EpisodeSheet extends StatelessWidget {
  const _EpisodeSheet({required this.api, required this.episode});

  final JellyfinApi api;
  final Episode episode;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final overview = episode.overview?.trim() ?? '';
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
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: const Text('Lire l\'épisode'),
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
