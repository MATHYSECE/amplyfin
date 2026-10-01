import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/item_details.dart';
import '../models/media_item.dart';
import '../models/session.dart';
import '../models/track_choice.dart';
import '../models/watch_progress.dart';
import '../services/download_manager.dart';
import '../services/offline_progress.dart';
import '../services/playback_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/details_page.dart';
import '../widgets/download_controls.dart';
import '../widgets/track_picker.dart';
import '../widgets/ui.dart';

/// Fiche d'un film : image de fond, affiche, infos, bouton lecture, résumé.
/// Le titre, l'année et l'affiche (déjà connus grâce à la grille) s'affichent
/// tout de suite ; le reste arrive quand le serveur a répondu.
class MovieScreen extends StatefulWidget {
  const MovieScreen({
    super.key,
    required this.api,
    required this.session,
    required this.movie,
    this.heroTag,
  });

  final JellyfinApi api;
  final Session session;
  final MediaItem movie;

  /// Nom de l'animation de l'affiche (celui de la grille par défaut).
  final String? heroTag;

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

  /// Vrai pendant la vérification avant la lecture.
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Demande la fiche complète au serveur. [keepTracks] : garde les pistes
  /// déjà choisies (mise à jour au retour du lecteur).
  /// Film téléchargé et serveur injoignable : la fiche gardée sur le
  /// téléphone (attente courte, pour ne pas rester bloqué hors ligne).
  Future<void> _load({bool keepTracks = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final local = _localDetails();
    try {
      final request = widget.api.getItemDetails(
        userId: widget.session.userId,
        itemId: widget.movie.id,
      );
      final details = local == null
          ? await request
          : await request.timeout(const Duration(seconds: 5));
      if (!mounted) return;
      setState(() {
        _details = details;
        if (!keepTracks) _presetTracks(details);
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        if (local != null) {
          _details = local;
          if (!keepTracks) _presetTracks(local);
        } else {
          _error = e is JellyfinException
              ? e.message
              : 'Le serveur ne répond pas.';
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fiche gardée avec le téléchargement (null si le film n'est pas
  /// téléchargé), avec la position de lecture du téléphone.
  ItemDetails? _localDetails() {
    final state = DownloadManager.instance.stateOf(widget.movie.id);
    final info = state.info;
    if (state.phase != DownloadPhase.complete || info == null) return null;
    final saved = OfflineProgress.instance.of(widget.movie.id);
    return info.toItemDetails(
      progress: saved?.toWatchProgress() ?? const WatchProgress(),
    );
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

  /// Vérifie avec le serveur si la lecture directe est possible (fenêtre
  /// d'explication sinon), puis ouvre le lecteur à la position [start].
  Future<void> _play({Duration start = Duration.zero}) async {
    if (_starting) return;
    setState(() => _starting = true);
    await launchPlayback(
      context,
      api: widget.api,
      session: widget.session,
      itemId: widget.movie.id,
      title: widget.movie.name,
      tracks: TrackSelection(
        audioIndex: _audioIndex,
        subtitleIndex: _subtitleIndex,
      ),
      start: start,
    );
    if (!mounted) return;
    setState(() => _starting = false);
    // Au retour : position et barre de progression à jour
    _load(keepTracks: true);
  }

  /// Bouton principal (« Lecture » ou « Reprendre à … »), pour un film
  /// commencé : où on en est et « Depuis le début », puis « Télécharger ».
  List<Widget> _buildPlayButtons(ItemDetails? details) {
    final progress = details?.progress ?? const WatchProgress();
    final resume = progress.canResume;
    final spinner = const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: AppColors.black,
      ),
    );
    return [
      FilledButton.icon(
        onPressed: () =>
            _play(start: resume ? progress.position : Duration.zero),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
        icon: _starting
            ? spinner
            : const Icon(Icons.play_arrow_rounded, size: 26),
        label: Text(resume ? progress.resumeLabel : 'Lecture'),
      ),
      if (resume) ...[
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ProgressLine(
                value: progress.fraction,
                height: 4,
                rounded: true,
              ),
            ),
            if (progress.remainingLabel(details?.runtime) case final left?) ...[
              const SizedBox(width: 12),
              Text(
                left,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ],
      const SizedBox(height: 14),
      _buildSecondaryButtons(details, resume: resume),
      OfflineNote(itemId: widget.movie.id),
    ];
  }

  /// « Depuis le début » (film commencé) et le bouton de téléchargement :
  /// côte à côte tant que rien n'est téléchargé, l'un sous l'autre sinon
  /// (la progression du téléchargement a besoin de place).
  Widget _buildSecondaryButtons(ItemDetails? details, {required bool resume}) {
    final restart = OutlinedButton.icon(
      onPressed: _starting ? null : () => _play(),
      icon: const Icon(Icons.replay_rounded, size: 22),
      label: const Text('Depuis le début'),
    );
    MovieDownloadButton download({bool compact = false}) => MovieDownloadButton(
      api: widget.api,
      userId: widget.session.userId,
      itemId: widget.movie.id,
      fileSize: details?.fileSize,
      compact: compact,
    );
    if (!resume) return download();

    final manager = DownloadManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        if (manager.stateOf(widget.movie.id).phase == DownloadPhase.none) {
          return Row(
            children: [
              Expanded(child: restart),
              const SizedBox(width: 10),
              Expanded(child: download(compact: true)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [restart, const SizedBox(height: 10), download()],
        );
      },
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
        heroTag: widget.heroTag,
        // Qualité du fichier : 4K, HEVC, HDR10, E-AC3 5.1…
        chips: details?.quality?.labels ?? const [],
      ),
      children: [
        ..._buildPlayButtons(details),
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
