import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api/device_profile.dart';
import '../api/jellyfin_api.dart';
import '../models/device_decoders.dart';
import '../models/media_track.dart';
import '../models/next_episode.dart';
import '../models/player_message.dart';
import '../models/playback_info.dart';
import '../models/playback_quality.dart';
import '../models/session.dart';
import '../models/subtitle_size.dart';
import '../models/track_choice.dart';
import '../services/device_capabilities.dart';
import '../services/download_manager.dart';
import '../services/next_episode_finder.dart';
import '../services/offline_progress.dart';
import '../services/player_preferences.dart';
import '../services/track_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/error_details.dart';
import '../widgets/next_episode_card.dart';
import '../widgets/player_controls.dart';
import '../widgets/subtitle_overlay.dart';
import '../widgets/track_picker.dart';
import '../widgets/transcode_dialog.dart';
import '../widgets/ui.dart';

/// Lecteur vidéo plein écran, à l'horizontale.
/// Par défaut le fichier original est lu tel quel (lecture directe) ;
/// le menu « Qualité » permet de demander un flux converti plus léger.
/// Les menus « Audio » et « Sous-titres » changent de piste en cours de route.
/// Pour un épisode, la carte « Épisode suivant » enchaîne sur le suivant
/// dans le même lecteur. En sortant, renvoie l'id du dernier élément lu.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.api,
    required this.session,
    required this.itemId,
    required this.title,
    this.subtitle,
    this.tracks = const TrackSelection(),
    this.start = Duration.zero,
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

  /// Position de départ (reprise de lecture).
  final Duration start;

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

  /// Erreur du moteur avant le démarrage : temps laissé à la vidéo pour
  /// démarrer quand même (le moteur essaie souvent une autre méthode). Un
  /// flux converti met plus longtemps à démarrer.
  static const _startupGrace = Duration(seconds: 6);
  static const _convertedStartupGrace = Duration(seconds: 20);

  final _player = Player(
    configuration: const PlayerConfiguration(
      bufferSize: _bufferSize,
      // En développement : messages détaillés du moteur vidéo
      logLevel: kDebugMode ? MPVLogLevel.info : MPVLogLevel.error,
    ),
  );

  /// Affichage de la vidéo (créé au démarrage, selon l'appareil).
  VideoController? _controller;

  /// Ce que la puce vidéo sait décoder (envoyé au serveur).
  DeviceDecoders _decoders = const DeviceDecoders();

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

  /// Dernier message d'erreur du moteur, nettoyé (« Voir le détail »).
  String? _errorDetail;

  /// Attente lancée par une erreur du moteur avant le démarrage.
  Timer? _startupErrorTimer;

  // ---------- Épisode suivant ----------

  /// Élément lu en ce moment (change quand on enchaîne sur l'épisode suivant).
  late String _itemId = widget.itemId;
  late String _title = widget.title;
  late String? _subtitle = widget.subtitle;

  /// Épisode qui suit (null pour un film, le dernier épisode, ou tant
  /// qu'il n'est pas connu).
  NextEpisode? _next;

  /// Début du générique de fin, s'il est connu du serveur.
  Duration? _outroStart;

  /// Vrai quand la carte « Épisode suivant » est affichée.
  bool _nextShown = false;

  /// « Regarder le générique » : carte cachée jusqu'à la fin (ou jusqu'à un
  /// retour en arrière avant le générique).
  bool _nextDismissed = false;

  /// Épisodes enchaînés tout seuls depuis le dernier appui sur l'écran.
  int _autoPlays = 0;

  /// Vrai pendant « Tu regardes toujours ? ».
  bool _askingStillWatching = false;

  /// Vrai pendant le passage à l'épisode suivant (fondu au noir).
  bool _switching = false;

  /// Vrai quand la vidéo avance (le compte à rebours de la carte aussi).
  final _playing = ValueNotifier<bool>(false);

  /// Évite de fermer deux fois le lecteur.
  bool _closing = false;

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
          if (!done || !mounted || _switching || _askingStillWatching) return;
          // Épisode terminé : le suivant, sinon retour à la fiche
          if (_next != null) {
            _autoAdvance();
          } else {
            _close();
          }
        }),
      )
      ..add(_player.stream.position.listen(_onPosition))
      ..add(
        _player.stream.playing.listen((playing) => _playing.value = playing),
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
    _decoders = await DeviceCapabilities.decoders();
    final controller = VideoController(
      _player,
      configuration: _videoConfiguration(),
    );
    if (!mounted) return;
    setState(() => _controller = controller);
    await _open(
      PlaybackQuality.original,
      start: widget.start,
      prefetched: widget.initialInfo,
    );
    _prepareNext();
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
    _startupErrorTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    // Prévient le serveur (il arrête une éventuelle conversion)
    final info = _info.value;
    if (info != null) {
      final position = _player.state.position;
      _report(() => widget.api.reportPlaybackStopped(info, position));
      if (info.isLocal) {
        // Fichier téléchargé : position gardée sur le téléphone, puis
        // envoyée au serveur s'il répond (après la fermeture de l'écran)
        final itemId = _itemId;
        final runtime = _player.state.duration;
        final api = widget.api;
        final userId = widget.session.userId;
        unawaited(
          Future(() async {
            await OfflineProgress.instance.record(
              itemId,
              position: position,
              runtime: runtime > Duration.zero ? runtime : null,
            );
            await OfflineProgress.instance.sync(api, userId);
          }),
        );
      }
    }
    _disposePlayer();
    _info.dispose();
    _sourceLabel.dispose();
    _controlsVisible.dispose();
    _playing.dispose();

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
    _startupErrorTimer?.cancel();
    _startupErrorTimer = null;
    setState(() {
      _opening = true;
      _error = null;
      _errorDetail = null;
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
            itemId: _itemId,
            quality: quality,
            start: start,
            // Ce que la puce ne lit pas est converti par le serveur
            decoders: _decoders,
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

      // Fichier téléchargé : lu depuis le téléphone, sans le serveur
      final localPath = info.localPath;
      await _player.open(
        localPath != null
            ? Media(localPath, start: start)
            : Media(
                widget.api.streamUrl(info),
                httpHeaders: widget.api.streamHeaders,
                start: start,
              ),
      );
      if (!mounted) return;
      _info.value = info;
      _sourceLabel.value = info.isLocal
          ? 'TÉLÉCHARGÉ'
          : info.directPlay
          ? 'ORIGINAL'
          : _convertsOnlyAudio(info)
          ? 'SON CONVERTI'
          : 'CONVERTI';
      setState(() => _quality = quality);
      _report(() => widget.api.reportPlaybackStart(info, start));
      await _applyTracks(info);
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Vrai si le serveur ne convertit que le son (image d'origine).
  bool _convertsOnlyAudio(PlaybackInfo info) =>
      info.convertsOnlyAudio(transcodeVideoCodecs(_decoders));

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
  /// [detail] : message du moteur, montré à la demande.
  Future<void> _offerTranscode({
    List<String> reasons = const ['VideoCodecNotSupported'],
    String? detail,
  }) async {
    if (!mounted) return;
    final position = _player.state.position;
    await _player.pause();
    if (!mounted) return;
    final convert = await showTranscodeDialog(
      context,
      reasonCodes: reasons,
      detail: detail,
    );
    if (!mounted) return;
    if (convert) {
      // Vraie conversion, reprise au même endroit
      _forceTranscode = true;
      await _open(_quality, start: position);
    } else {
      _close();
    }
  }

  /// Erreur signalée par le lecteur lui-même (fichier illisible, coupure…).
  /// Le moteur signale aussi des erreurs sans gravité (il essaie une autre
  /// méthode et la lecture continue) : on ne prévient que si la vidéo n'a
  /// toujours pas démarré quelques secondes plus tard.
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
    _errorDetail = cleanPlayerMessage(message);
    final converted = _info.value?.directPlay == false;
    _startupErrorTimer ??= Timer(
      converted ? _convertedStartupGrace : _startupGrace,
      _onStartupFailed,
    );
  }

  /// La vidéo n'a pas démarré après une erreur du moteur : en lecture
  /// directe depuis le serveur, on propose de convertir ; sinon, message.
  void _onStartupFailed() {
    _startupErrorTimer = null;
    if (!mounted || _error != null || _closing) return;
    if (_player.state.duration > Duration.zero) return;
    final info = _info.value;
    if (info != null &&
        info.directPlay &&
        !info.isLocal &&
        !_decodeProblemShown) {
      _decodeProblemShown = true;
      _offerTranscode(reasons: const ['DirectPlayError'], detail: _errorDetail);
      return;
    }
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
    // Fichier téléchargé : position aussi gardée sur le téléphone (si
    // l'appli est fermée en pleine lecture, on reprend quand même)
    if (info.isLocal) {
      OfflineProgress.instance.record(
        _itemId,
        position: state.position,
        runtime: state.duration > Duration.zero ? state.duration : null,
      );
    }
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

  // ---------- Épisode suivant ----------

  /// Cherche l'épisode qui suit (et le début du générique de fin) pendant
  /// la lecture de l'épisode actuel.
  Future<void> _prepareNext() async {
    final itemId = _itemId;
    final next = await findNextEpisode(
      widget.api,
      userId: widget.session.userId,
      itemId: itemId,
    );
    if (next == null || !mounted || itemId != _itemId) return;
    final outroStart = await findOutroStart(widget.api, itemId);
    if (!mounted || itemId != _itemId) return;
    setState(() {
      _next = next;
      _outroStart = outroStart;
    });
    _onPosition(_player.state.position);
  }

  /// Affiche la carte « Épisode suivant » pendant le générique de fin.
  void _onPosition(Duration position) {
    final trigger = _next == null
        ? null
        : nextEpisodeTrigger(_player.state.duration, outroStart: _outroStart);
    final inCredits = trigger != null && position >= trigger;
    // Retour en arrière avant le générique : la carte pourra revenir
    if (!inCredits) _nextDismissed = false;
    final show =
        inCredits &&
        !_nextDismissed &&
        !_switching &&
        !_askingStillWatching &&
        _error == null;
    if (show != _nextShown && mounted) setState(() => _nextShown = show);
  }

  /// Fin du compte à rebours (ou de l'épisode) : le suivant, sauf après
  /// plusieurs épisodes enchaînés sans toucher l'écran.
  void _autoAdvance() {
    if (_switching || _askingStillWatching || _next == null) return;
    if (_autoPlays >= stillWatchingAfter) {
      _player.pause();
      setState(() {
        _askingStillWatching = true;
        _nextShown = false;
      });
      return;
    }
    _autoPlays++;
    _playNext();
  }

  /// Enchaîne sur l'épisode suivant dans le même lecteur : fondu au noir,
  /// épisode actuel compté comme vu, puis le suivant avec les mêmes langues.
  Future<void> _playNext() async {
    final next = _next;
    if (next == null || _switching) return;
    final current = _info.value;
    final duration = _player.state.duration;
    setState(() {
      _switching = true;
      _nextShown = false;
      _askingStillWatching = false;
    });
    await _player.pause();
    final languages = await _languagesFor(next, current);
    await Future<void>.delayed(AppDurations.emphasized);
    if (!mounted) return;

    // Fin de l'épisode actuel : signalée à la fin du fichier, pour qu'il
    // compte comme vu (même si le générique n'est pas terminé)
    if (current != null) {
      _report(() => widget.api.reportPlaybackStopped(current, duration));
      if (current.isLocal) {
        await OfflineProgress.instance.record(
          _itemId,
          position: duration,
          runtime: duration > Duration.zero ? duration : null,
        );
      }
    }
    final tracks = languages.resolve(next.tracks, player: _decoders.player);
    setState(() {
      _itemId = next.itemId;
      _title = next.title;
      _subtitle = next.subtitle;
      _tracks = tracks;
      _next = null;
      _outroStart = null;
      _nextDismissed = false;
      _decodeProblemShown = false;
    });
    // Ancienne séance déjà signalée terminée : _open ne la signale pas
    _info.value = null;
    _sourceLabel.value = null;
    await _player.stop();

    // Téléchargé : lu depuis le téléphone. Sinon, le serveur dit comment
    // le lire (même qualité qu'avant)
    var info = await DownloadManager.instance.localPlayback(next.itemId);
    // Son du fichier téléchargé illisible (TrueHD…) : flux du serveur
    final localAudio = info?.track(tracks.audioIndex ?? info.defaultAudioIndex);
    if (localAudio != null && !_decoders.player.playsAudio(localAudio)) {
      info = null;
    }
    if (info == null) {
      try {
        info = await widget.api.getPlaybackInfo(
          userId: widget.session.userId,
          itemId: next.itemId,
          quality: _quality,
          start: next.start,
          decoders: _decoders,
          tracks: tracks,
          allowDirectPlay: !_forceTranscode,
        );
      } on JellyfinException catch (e) {
        if (mounted) {
          setState(() {
            _error = e.message;
            _switching = false;
          });
        }
        return;
      }
    }
    if (!mounted) return;
    // Lecture directe impossible : on demande, comme avant le 1er épisode,
    // sauf si la conversion était déjà acceptée pour l'épisode précédent
    // (seul le son à convertir : pas de question)
    final alreadyConverted =
        current != null && !current.directPlay && !_convertsOnlyAudio(current);
    if (!info.directPlay &&
        !_convertsOnlyAudio(info) &&
        _quality.isOriginal &&
        !_forceTranscode &&
        !alreadyConverted) {
      final convert = await showTranscodeDialog(
        context,
        reasonCodes: info.transcodeReasons,
      );
      if (!mounted) return;
      if (!convert) {
        _close();
        return;
      }
    }
    await _open(_quality, start: next.start, prefetched: info);
    if (_error == null) await _waitForVideo(next.start);
    if (!mounted) return;
    setState(() => _switching = false);
    _prepareNext();
  }

  /// Langues à garder pour l'épisode suivant : celles écoutées en ce moment,
  /// sinon celles choisies pour la série.
  Future<LanguagePreference> _languagesFor(
    NextEpisode next,
    PlaybackInfo? current,
  ) async {
    final seriesId = next.seriesId;
    final saved = seriesId == null
        ? const LanguagePreference()
        : await TrackPreferences().load(seriesId);
    if (current == null) return saved;
    final subtitleIndex = _tracks.subtitleIndex;
    return LanguagePreference(
      audioLanguage:
          current.track(_tracks.audioIndex)?.language ?? saved.audioLanguage,
      subtitleLanguage: subtitleIndex == TrackSelection.noSubtitles
          ? LanguagePreference.noSubtitles
          : current.track(subtitleIndex)?.language ?? saved.subtitleLanguage,
    );
  }

  /// Attend que la nouvelle vidéo démarre vraiment (30 s au plus : une
  /// conversion peut être longue à démarrer), pour lever le fondu au noir
  /// sur l'image et pas sur un écran vide.
  Future<void> _waitForVideo(Duration start) async {
    bool started(Duration position) =>
        position > start + const Duration(milliseconds: 300);
    if (started(_player.state.position)) return;
    try {
      await _player.stream.position
          .firstWhere(started)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      // Tant pis : le fondu se lève quand même
    }
  }

  /// « Tu regardes toujours ? » → Continuer.
  void _continueWatching() {
    _autoPlays = 0;
    _playNext();
  }

  /// Ferme le lecteur en renvoyant l'élément lu en dernier (la fiche série
  /// s'ouvre alors sur sa saison).
  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(_itemId);
  }

  // ---------- Pistes audio et sous-titres ----------

  /// Applique les pistes choisies une fois la vidéo ouverte. Sans choix
  /// précis, on prend celles proposées par le serveur (préférences Jellyfin).
  Future<void> _applyTracks(PlaybackInfo info) async {
    var subtitleIndex =
        _tracks.subtitleIndex ??
        info.defaultSubtitleIndex ??
        TrackSelection.noSubtitles;
    // Sous-titres que le lecteur ne sait pas afficher (PGS) : aucun
    final subtitle = info.track(subtitleIndex);
    if (subtitle != null && !_decoders.player.showsSubtitle(subtitle)) {
      subtitleIndex = TrackSelection.noSubtitles;
    }
    _tracks = TrackSelection(
      audioIndex: _tracks.audioIndex ?? info.defaultAudioIndex,
      subtitleIndex: subtitleIndex,
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
          audioTrackOption(track, _decoders.player, local: info.isLocal),
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
    // Son que le lecteur ne lit pas (TrueHD…) : le serveur le convertit
    final track = info.track(chosen.value);
    final playable = track == null || _decoders.player.playsAudio(track);
    if (info.directPlay && playable) {
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
          subtitleTrackOption(track, _decoders.player),
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
    final info = _info.value;
    final convertedOriginal = info?.directPlay == false;
    final onlyAudio = info != null && _convertsOnlyAudio(info);
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
                : onlyAudio
                ? 'Image d\'origine, son converti par le serveur'
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
    final next = _next;
    final insets = MediaQuery.paddingOf(context);

    return PopScope(
      // Retour du téléphone : on passe par _close (renvoie l'élément lu)
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: Listener(
          // Un appui sur l'écran : on regarde bien (« Tu regardes toujours ? »)
          onPointerDown: (_) => _autoPlays = 0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (controller != null) ...[
                // La vidéo seule (commandes et sous-titres de media_kit
                // désactivés)
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
                  title: _title,
                  subtitle: _subtitle,
                  sourceLabel: _sourceLabel,
                  onBack: _close,
                  onAudio: _chooseAudio,
                  onSubtitles: _chooseSubtitles,
                  onQuality: _chooseQuality,
                  onVisibleChanged: (visible) =>
                      _controlsVisible.value = visible,
                ),
              ],
              // Fondu au noir pendant le passage à l'épisode suivant
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _switching ? 1 : 0,
                  duration: AppDurations.emphasized,
                  curve: Curves.easeInOut,
                  child: const ColoredBox(color: AppColors.black),
                ),
              ),
              if (_switching || (_opening && _info.value == null))
                const Center(child: CircularProgressIndicator()),
              // Carte « Épisode suivant », au-dessus de la barre de
              // lecture quand les commandes sont affichées
              Positioned(
                right: insets.right + 24,
                bottom: 0,
                child: ValueListenableBuilder(
                  valueListenable: _controlsVisible,
                  builder: (context, raised, child) => AnimatedPadding(
                    padding: EdgeInsets.only(bottom: raised ? 108 : 24),
                    duration: AppDurations.medium,
                    curve: Curves.easeOutCubic,
                    child: child,
                  ),
                  child: AnimatedSwitcher(
                    duration: AppDurations.emphasized,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0.15, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _nextShown && next != null
                        ? SizedBox(
                            key: ValueKey(next.itemId),
                            width: 460,
                            child: NextEpisodeCard(
                              episode: next,
                              running: _playing,
                              onPlayNow: _playNext,
                              onTimeout: _autoAdvance,
                              onDismiss: () => setState(() {
                                _nextDismissed = true;
                                _nextShown = false;
                              }),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
              if (_askingStillWatching && next != null)
                StillWatchingOverlay(
                  episode: next,
                  onContinue: _continueWatching,
                  onStop: _close,
                ),
              if (_error != null)
                _ErrorOverlay(
                  message: _error!,
                  detail: _errorDetail,
                  onRetry: () => _open(_quality, start: _player.state.position),
                  onBack: _close,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Message d'erreur par-dessus la vidéo, avec « Retour » et « Réessayer ».
class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({
    required this.message,
    this.detail,
    required this.onRetry,
    required this.onBack,
  });

  final String message;

  /// Message technique du moteur, montré à la demande.
  final String? detail;
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
              if (detail != null) ...[
                const SizedBox(height: 8),
                ErrorDetails(detail!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
