import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api/jellyfin_api.dart';
import '../models/media_track.dart';
import '../models/playback_info.dart';
import '../models/playback_quality.dart';
import '../models/session.dart';
import '../models/subtitle_size.dart';
import '../models/track_choice.dart';
import '../services/device_capabilities.dart';
import '../services/player_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/player_controls.dart';
import '../widgets/subtitle_overlay.dart';
import '../widgets/track_picker.dart';
import '../widgets/transcode_dialog.dart';
import '../widgets/ui.dart';

/// Lecteur vidéo plein écran, à l'horizontale.
/// Par défaut le fichier original est lu tel quel (lecture directe) ;
/// le menu « Qualité » permet de demander un flux converti plus léger.
/// Les menus « Audio » et « Sous-titres » changent de piste en cours de route.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.api,
    required this.session,
    required this.itemId,
    required this.title,
    this.subtitle,
    this.tracks = const TrackSelection(),
    this.initialInfo,
  });

  final JellyfinApi api;
  final Session session;

  /// Film ou épisode à lire.
  final String itemId;

  /// Titre affiché en haut du lecteur (le film, ou la série).
  final String title;

  /// Petite ligne sous le titre (ex. « S1 · É3 · Titre »), facultative.
  final String? subtitle;

  /// Pistes audio et sous-titres choisies avant la lecture.
  final TrackSelection tracks;

  /// Réponse du serveur déjà obtenue avant d'ouvrir le lecteur (la fiche
  /// vérifie si la lecture directe est possible) : évite de redemander.
  final PlaybackInfo? initialInfo;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  /// Fréquence des signalements de position au serveur.
  static const _progressInterval = Duration(seconds: 10);

  /// Mémoire tampon du lecteur : 64 Mo, confortable pour de la 4K.
  static const _bufferSize = 64 * 1024 * 1024;

  /// Sous-titres à part : nouveaux essais avant d'abandonner (le serveur,
  /// occupé à préparer la vidéo, ne les fournit pas toujours du premier coup).
  static const _subtitleRetries = 3;
  static const _subtitleRetryDelay = Duration(seconds: 3);

  final _player = Player(
    configuration: const PlayerConfiguration(
      bufferSize: _bufferSize,
      // En développement : messages détaillés du moteur vidéo
      logLevel: kDebugMode ? MPVLogLevel.info : MPVLogLevel.error,
    ),
  );

  /// Affichage de la vidéo (créé au démarrage, selon l'appareil).
  VideoController? _controller;

  /// Vrai sur l'émulateur Android (son décodeur ne lit pas le 10 bits).
  bool _onEmulator = false;

  /// Vrai quand l'appareil n'a pas réussi à décoder l'image en lecture
  /// directe et que l'utilisateur a accepté une vraie conversion.
  bool _forceTranscode = false;

  /// Évite de montrer deux fois la fenêtre « lecture directe impossible ».
  bool _decodeProblemShown = false;

  /// Nouveaux essais déjà faits pour les sous-titres à part actuels.
  int _subtitleAttempts = 0;

  /// Vrai pendant l'attente avant un nouvel essai des sous-titres.
  bool _subtitleRetryPending = false;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _progressTimer;

  /// Séance de lecture en cours (null tant que la vidéo n'est pas ouverte).
  /// ValueNotifier : les commandes de media_kit ne se redessinent pas seules,
  /// la mention ORIGINAL / CONVERTI écoute donc directement cette valeur.
  final _info = ValueNotifier<PlaybackInfo?>(null);

  /// Mention affichée en haut du lecteur : « ORIGINAL », « CONVERTI », ou
  /// « CONVERSION… » pendant qu'un flux converti se prépare.
  final _sourceLabel = ValueNotifier<String?>(null);
  PlaybackQuality _quality = PlaybackQuality.original;

  /// Pistes actuelles (gardées si on change de qualité).
  late TrackSelection _tracks = widget.tracks;

  /// Taille des sous-titres (retenue sur le téléphone).
  final _preferences = PlayerPreferences();
  SubtitleSize _subtitleSize = SubtitleSize.medium;

  /// Vrai quand les commandes sont affichées (les sous-titres remontent).
  final _controlsVisible = ValueNotifier<bool>(true);
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Plein écran, téléphone à l'horizontale
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _subscriptions
      ..add(_player.stream.error.listen(_onPlayerError))
      ..add(
        _player.stream.completed.listen((done) {
          // Film terminé : on revient à la fiche
          if (done && mounted) Navigator.of(context).maybePop();
        }),
      );
    _subscriptions.add(
      _player.stream.log.listen((log) {
        if (kDebugMode) {
          // Messages du moteur vidéo dans la console (diagnostic)
          debugPrint('mpv ${log.level} [${log.prefix}] ${log.text}');
        }
        _watchForDecodeProblem(log);
      }),
    );
    _progressTimer = Timer.periodic(
      _progressInterval,
      (_) => _reportProgress(),
    );
    _loadSubtitleSize();
    _start();
  }

  Future<void> _loadSubtitleSize() async {
    final size = await _preferences.loadSubtitleSize();
    if (mounted) setState(() => _subtitleSize = size);
  }

  /// Prépare l'affichage puis lance le film.
  Future<void> _start() async {
    _onEmulator = await DeviceCapabilities.isAndroidEmulator();
    final controller = VideoController(
      _player,
      configuration: _videoConfiguration(),
    );
    if (!mounted) return;
    setState(() => _controller = controller);
    await _open(PlaybackQuality.original, prefetched: widget.initialInfo);
  }

  /// Réglage de l'affichage vidéo. Sur Android, la puce vidéo décode l'image
  /// et l'affiche elle-même à l'écran (comme les lecteurs natifs) : c'est le
  /// seul moyen de lire la HEVC 10 bits ou la 4K de façon fluide. Avec le
  /// réglage par défaut de media_kit, la puce n'a pas accès à l'écran et le
  /// processeur, trop lent, prend le relais (et l'émulateur reste noir).
  VideoControllerConfiguration _videoConfiguration() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const VideoControllerConfiguration(
        vo: 'mediacodec_embed',
        hwdec: 'mediacodec',
      );
    }
    return const VideoControllerConfiguration();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    // Prévient le serveur (il arrête une éventuelle conversion)
    final info = _info.value;
    if (info != null) {
      final position = _player.state.position;
      _report(() => widget.api.reportPlaybackStopped(info, position));
    }
    _disposePlayer();
    _info.dispose();
    _sourceLabel.dispose();
    _controlsVisible.dispose();

    // Retour à l'affichage normal
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  /// Arrête d'abord la lecture (le décodeur vidéo libère l'écran),
  /// puis libère le lecteur. Libérer directement peut bloquer l'appli.
  Future<void> _disposePlayer() async {
    await _player.stop();
    await _player.dispose();
  }

  /// Demande au serveur comment lire le film dans la [quality] voulue,
  /// puis ouvre la vidéo à la position [start].
  /// [prefetched] : réponse du serveur déjà obtenue (pas de nouvelle demande).
  Future<void> _open(
    PlaybackQuality quality, {
    Duration start = Duration.zero,
    PlaybackInfo? prefetched,
  }) async {
    setState(() {
      _opening = true;
      _error = null;
    });
    // Pendant le chargement, plus d'ancienne mention qui serait fausse
    final converting =
        !quality.isOriginal ||
        _forceTranscode ||
        (prefetched != null && !prefetched.directPlay);
    _sourceLabel.value = converting ? 'CONVERSION…' : null;
    try {
      final info =
          prefetched ??
          await widget.api.getPlaybackInfo(
            userId: widget.session.userId,
            itemId: widget.itemId,
            quality: quality,
            start: start,
            // Le décodeur vidéo de l'émulateur ne sait pas lire le 10 bits :
            // le serveur convertit alors ces vidéos
            supports10Bit: !_onEmulator,
            tracks: _tracks,
            allowDirectPlay: !_forceTranscode,
          );
      if (!mounted) return;

      // Changement de qualité : l'ancienne séance est terminée
      final previous = _info.value;
      if (previous != null) {
        _report(() => widget.api.reportPlaybackStopped(previous, start));
        // Oublie l'ancienne vidéo (pistes, durée) avant d'ouvrir la nouvelle :
        // les pistes de la nouvelle seront appliquées une fois connues
        await _player.stop();
      }

      await _player.open(
        Media(
          widget.api.streamUrl(info),
          httpHeaders: widget.api.streamHeaders,
          start: start,
        ),
      );
      if (!mounted) return;
      _info.value = info;
      _sourceLabel.value = info.directPlay ? 'ORIGINAL' : 'CONVERTI';
      setState(() => _quality = quality);
      _report(() => widget.api.reportPlaybackStart(info, start));
      await _applyTracks(info);
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Surveille les messages du moteur : en lecture directe, s'il n'arrive
  /// pas à afficher l'image (décodeur ou affichage impossible), on propose
  /// de convertir. Les autres erreurs, sans gravité, sont ignorées.
  void _watchForDecodeProblem(PlayerLog log) {
    final info = _info.value;
    if (_decodeProblemShown || info == null || !info.directPlay) return;
    if (!info.hasVideo || (log.level != 'fatal' && log.level != 'error')) {
      return;
    }
    final text = log.text.toLowerCase();
    if (text.contains('video chain') || text.contains('video_out')) {
      _decodeProblemShown = true;
      _offerTranscode();
    }
  }

  /// Fenêtre « lecture directe impossible » pendant la lecture.
  Future<void> _offerTranscode() async {
    if (!mounted) return;
    final position = _player.state.position;
    await _player.pause();
    if (!mounted) return;
    final convert = await showTranscodeDialog(
      context,
      reasonCodes: const ['VideoCodecNotSupported'],
    );
    if (!mounted) return;
    if (convert) {
      // Vraie conversion, reprise au même endroit
      _forceTranscode = true;
      await _open(_quality, start: position);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  /// Erreur signalée par le lecteur lui-même (fichier illisible, coupure…).
  /// Le moteur signale aussi des erreurs sans gravité (il essaie une autre
  /// méthode et la lecture continue) : on ne prévient que si la vidéo n'a
  /// jamais pu démarrer.
  void _onPlayerError(String message) {
    if (!mounted || _error != null) return;
    if (message.contains('/Subtitles/')) {
      _onSubtitleError();
      return;
    }
    // Décodeur refusé : le moteur essaie aussitôt une autre méthode.
    // Si l'image ne peut vraiment pas s'afficher, _watchForDecodeProblem
    // propose de convertir.
    if (message.contains('Could not open codec')) return;
    if (_player.state.duration > Duration.zero) return;
    // Jamais le message brut du moteur : il peut contenir l'adresse du
    // serveur et la clé de connexion
    setState(() => _error = 'La vidéo n\'a pas pu être lue.');
  }

  /// Sous-titres à part impossibles à télécharger : nouvel essai quelques
  /// secondes plus tard, puis, après plusieurs échecs, la vidéo continue sans.
  Future<void> _onSubtitleError() async {
    final info = _info.value;
    final index = _tracks.subtitleIndex;
    // Le moteur signale chaque échec deux fois : une seule réaction
    // (essai déjà prévu, ou sous-titres déjà abandonnés)
    if (_subtitleRetryPending ||
        info == null ||
        index == null ||
        index == TrackSelection.noSubtitles) {
      return;
    }
    if (_subtitleAttempts < _subtitleRetries) {
      _subtitleAttempts++;
      _subtitleRetryPending = true;
      await Future<void>.delayed(_subtitleRetryDelay);
      _subtitleRetryPending = false;
      // Entre-temps, on a pu changer de vidéo ou de sous-titres
      if (!mounted || _info.value != info || _tracks.subtitleIndex != index) {
        return;
      }
      await _applySubtitles(info, index, retry: true);
      return;
    }
    _tracks = TrackSelection(
      audioIndex: _tracks.audioIndex,
      subtitleIndex: TrackSelection.noSubtitles,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ces sous-titres n\'ont pas pu être chargés.'),
      ),
    );
  }

  void _reportProgress() {
    final info = _info.value;
    if (info == null) return;
    final state = _player.state;
    _report(
      () => widget.api.reportPlaybackProgress(
        info,
        state.position,
        isPaused: !state.playing,
      ),
    );
  }

  /// Signale au serveur sans gêner la lecture : une erreur ici est ignorée.
  Future<void> _report(Future<void> Function() call) async {
    try {
      await call();
    } on JellyfinException {
      // Pas grave : le film continue de se lire
    }
  }

  // ---------- Pistes audio et sous-titres ----------

  /// Applique les pistes choisies une fois la vidéo ouverte. Sans choix
  /// précis, on prend celles proposées par le serveur (préférences Jellyfin).
  Future<void> _applyTracks(PlaybackInfo info) async {
    _tracks = TrackSelection(
      audioIndex: _tracks.audioIndex ?? info.defaultAudioIndex,
      subtitleIndex:
          _tracks.subtitleIndex ??
          info.defaultSubtitleIndex ??
          TrackSelection.noSubtitles,
    );
    await _waitForTracks();
    if (!mounted) return;
    await _applyAudio(info, _tracks.audioIndex);
    await _applySubtitles(info, _tracks.subtitleIndex!);
  }

  /// Attend que le lecteur ait lu la liste des pistes du fichier.
  Future<void> _waitForTracks() async {
    // « auto » et « no » sont toujours dans la liste : il faut plus que ça
    bool ready(Tracks tracks) =>
        tracks.audio.length > 2 || tracks.video.length > 2;
    if (ready(_player.state.tracks)) return;
    try {
      await _player.stream.tracks
          .firstWhere(ready)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      // Tant pis : le lecteur garde ses pistes par défaut
    }
  }

  /// Piste audio. En flux converti, le serveur n'envoie que la piste
  /// demandée : rien à faire côté lecteur.
  Future<void> _applyAudio(PlaybackInfo info, int? index) async {
    if (!info.directPlay) return;
    final track = info.track(index);
    final id = track == null ? null : playerTrackId(info.tracks, track);
    if (id != null) await _player.setAudioTrack(AudioTrack('$id', null, null));
  }

  /// Sous-titres : aucun, fichier à part (téléchargé par son adresse),
  /// ou piste du fichier vidéo. [retry] : nouvel essai après un échec.
  Future<void> _applySubtitles(
    PlaybackInfo info,
    int index, {
    bool retry = false,
  }) async {
    if (!retry) _subtitleAttempts = 0;
    final track = info.track(index);
    if (track == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final url = track.deliveryUrl;
    if (track.deliveryMethod == 'External' && url != null) {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          widget.api.absoluteUrl(url),
          title: track.label,
          language: track.language,
        ),
      );
    } else if (info.directPlay) {
      final id = playerTrackId(info.tracks, track);
      if (id != null) {
        await _player.setSubtitleTrack(SubtitleTrack('$id', null, null));
      }
    } else if (track.deliveryMethod == 'Encode') {
      // Flux converti : le serveur a incrusté les sous-titres dans l'image
      await _player.setSubtitleTrack(SubtitleTrack.no());
    } else {
      await _player.setSubtitleTrack(SubtitleTrack.auto());
    }
  }

  /// Menu « Audio ».
  Future<void> _chooseAudio() async {
    final info = _info.value;
    if (info == null) return;
    final chosen = await showPicker(
      context,
      title: 'Audio',
      options: [
        for (final track in info.audioTracks)
          PickerOption<int?>(track.index, track.label),
      ],
      selected: _tracks.audioIndex,
    );
    if (chosen == null || chosen.value == _tracks.audioIndex || !mounted) {
      return;
    }
    _tracks = TrackSelection(
      audioIndex: chosen.value,
      subtitleIndex: _tracks.subtitleIndex,
    );
    if (info.directPlay) {
      // Le lecteur a tout le fichier : changement immédiat
      await _applyAudio(info, chosen.value);
    } else {
      // Flux converti : on redemande un flux avec cette piste, au même endroit
      await _open(_quality, start: _player.state.position);
    }
  }

  /// Menu « Sous-titres ».
  Future<void> _chooseSubtitles() async {
    final info = _info.value;
    if (info == null) return;
    final chosen = await showPicker(
      context,
      title: 'Sous-titres',
      options: [
        const PickerOption(TrackSelection.noSubtitles, 'Aucun'),
        for (final track in info.subtitleTracks)
          PickerOption(track.index, track.label),
      ],
      selected: _tracks.subtitleIndex ?? TrackSelection.noSubtitles,
      extra: PickerExtra(
        icon: Icons.format_size_rounded,
        label: 'Taille des sous-titres',
        value: _subtitleSize.label,
        onTap: _chooseSubtitleSize,
      ),
    );
    if (chosen == null || chosen.value == _tracks.subtitleIndex || !mounted) {
      return;
    }
    _tracks = TrackSelection(
      audioIndex: _tracks.audioIndex,
      subtitleIndex: chosen.value,
    );
    if (info.directPlay) {
      await _applySubtitles(info, chosen.value);
    } else {
      await _open(_quality, start: _player.state.position);
    }
  }

  /// Menu « Taille des sous-titres » (retenue pour les prochaines lectures).
  Future<void> _chooseSubtitleSize() async {
    final chosen = await showPicker(
      context,
      title: 'Taille des sous-titres',
      options: [
        for (final size in SubtitleSize.values) PickerOption(size, size.label),
      ],
      selected: _subtitleSize,
    );
    if (chosen == null || !mounted) return;
    setState(() => _subtitleSize = chosen.value);
    await _preferences.saveSubtitleSize(chosen.value);
  }

  /// Menu « Qualité » : choisir une qualité relance la vidéo au même endroit.
  Future<void> _chooseQuality() async {
    // Qualité « originale » mais fichier converti (lecture directe impossible)
    final convertedOriginal = _info.value?.directPlay == false;
    final chosen = await showPicker(
      context,
      title: 'Qualité',
      options: [
        for (final quality in PlaybackQuality.all)
          PickerOption(
            quality,
            quality.label,
            description: !quality.isOriginal
                ? 'Converti par le serveur'
                : convertedOriginal
                ? 'Définition d\'origine, mais convertie : '
                      'lecture directe impossible sur cet appareil'
                : 'Fichier lu tel quel, sans conversion',
          ),
      ],
      selected: _quality,
    );
    if (chosen == null || chosen.value == _quality || !mounted) return;
    await _open(chosen.value, start: _player.state.position);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null) ...[
            // La vidéo seule (commandes et sous-titres de media_kit désactivés)
            Video(
              controller: controller,
              controls: NoVideoControls,
              subtitleViewConfiguration: const SubtitleViewConfiguration(
                visible: false,
              ),
            ),
            // Nos sous-titres, sous les commandes
            SubtitleOverlay(
              player: _player,
              size: _subtitleSize,
              raised: _controlsVisible,
            ),
            // Nos commandes, dessinées comme sur la maquette
            PlayerControls(
              player: _player,
              title: widget.title,
              subtitle: widget.subtitle,
              sourceLabel: _sourceLabel,
              onBack: () => Navigator.of(context).maybePop(),
              onAudio: _chooseAudio,
              onSubtitles: _chooseSubtitles,
              onQuality: _chooseQuality,
              onVisibleChanged: (visible) => _controlsVisible.value = visible,
            ),
          ],
          if (_opening && _info.value == null)
            const Center(child: CircularProgressIndicator()),
          if (_error != null)
            _ErrorOverlay(
              message: _error!,
              onRetry: () => _open(_quality, start: _player.state.position),
              onBack: () => Navigator.of(context).maybePop(),
            ),
        ],
      ),
    );
  }
}

/// Message d'erreur par-dessus la vidéo, avec « Retour » et « Réessayer ».
class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return GlowBackground(
      center: Alignment.topCenter,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppColors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: onBack,
                    child: const Text('Retour'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
