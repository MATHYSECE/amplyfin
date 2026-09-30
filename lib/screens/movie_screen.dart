import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/item_details.dart';
import '../models/media_item.dart';
import '../models/session.dart';
import '../models/track_choice.dart';
import '../widgets/details_page.dart';
import '../widgets/track_picker.dart';
import '../widgets/ui.dart';
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
  final MediaItem movie;

  @override
  State<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> {
  ItemDetails? _details;
  bool _loading = false;
  String? _error;

  // Pistes choisies avant la lecture (numéros sur le serveur)
  int? _audioIndex;
  int _subtitleIndex = TrackSelection.noSubtitles;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Demande la fiche complète au serveur.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = await widget.api.getItemDetails(
        userId: widget.session.userId,
        itemId: widget.movie.id,
      );
      if (!mounted) return;
      setState(() {
        _details = details;
        _presetTracks(details);
      });
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Présélection : le choix proposé par le serveur (préférences Jellyfin
  /// de l'utilisateur), sinon la piste audio marquée « par défaut ».
  void _presetTracks(ItemDetails details) {
    final audios = details.audioTracks;
    final serverAudio = audios
        .where((t) => t.index == details.defaultAudioIndex)
        .firstOrNull;
    _audioIndex =
        (serverAudio ??
                audios.where((t) => t.isDefault).firstOrNull ??
                audios.firstOrNull)
            ?.index;

    final serverSubtitle = details.subtitleTracks
        .where((t) => t.index == details.defaultSubtitleIndex)
        .firstOrNull;
    _subtitleIndex = serverSubtitle?.index ?? TrackSelection.noSubtitles;
  }

  Future<void> _chooseAudio(ItemDetails details) async {
    final chosen = await showPicker(
      context,
      title: 'Audio',
      options: [
        for (final track in details.audioTracks)
          PickerOption<int?>(track.index, track.label),
      ],
      selected: _audioIndex,
    );
    if (chosen != null) setState(() => _audioIndex = chosen.value);
  }

  Future<void> _chooseSubtitles(ItemDetails details) async {
    final chosen = await showPicker(
      context,
      title: 'Sous-titres',
      options: [
        const PickerOption(TrackSelection.noSubtitles, 'Aucun'),
        for (final track in details.subtitleTracks)
          PickerOption(track.index, track.label),
      ],
      selected: _subtitleIndex,
    );
    if (chosen != null) setState(() => _subtitleIndex = chosen.value);
  }

  void _play() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          api: widget.api,
          session: widget.session,
          itemId: widget.movie.id,
          title: widget.movie.name,
          tracks: TrackSelection(
            audioIndex: _audioIndex,
            subtitleIndex: _subtitleIndex,
          ),
        ),
      ),
    );
  }

  /// Bloc en verre avec les deux choix « Audio » et « Sous-titres ».
  Widget _buildTrackSelectors(ItemDetails details) {
    final audio = details.audioTracks
        .where((t) => t.index == _audioIndex)
        .firstOrNull;
    final subtitle = details.subtitleTracks
        .where((t) => t.index == _subtitleIndex)
        .firstOrNull;
    return GlassPanel(
      child: Column(
        children: [
          TrackSelectorTile(
            icon: Icons.volume_up_outlined,
            title: 'Audio',
            value: audio?.label ?? 'Par défaut',
            onTap: details.audioTracks.length > 1
                ? () => _chooseAudio(details)
                : null,
          ),
          const Divider(indent: 16, endIndent: 16),
          TrackSelectorTile(
            icon: Icons.subtitles_outlined,
            title: 'Sous-titres',
            value: details.subtitleTracks.isEmpty
                ? 'Aucun disponible'
                : (subtitle?.label ?? 'Aucun'),
            onTap: details.subtitleTracks.isEmpty
                ? null
                : () => _chooseSubtitles(details),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final details = _details;

    return DetailsPage(
      api: widget.api,
      item: movie,
      details: details,
      showBackdropFallback: !_loading,
      header: DetailsHeader(
        api: widget.api,
        item: movie,
        infos: [
          if (movie.year != null) '${movie.year}',
          ?details?.runtimeLabel,
          ?details?.officialRating,
        ],
        rating: details?.ratingLabel,
        // Qualité du fichier : 4K, HEVC, HDR10, E-AC3 5.1…
        chips: details?.quality?.labels ?? const [],
      ),
      children: [
        FilledButton.icon(
          onPressed: _play,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
          icon: const Icon(Icons.play_arrow_rounded, size: 26),
          label: const Text('Lecture'),
        ),
        const SizedBox(height: 18),
        if (details != null) ...[
          _buildTrackSelectors(details),
          const SizedBox(height: 22),
          DetailsOverview(details: details),
        ] else if (_error != null)
          RetryMessage(message: _error!, onRetry: _load)
        else
          const DetailsOverviewSkeleton(),
      ],
    );
  }
}
