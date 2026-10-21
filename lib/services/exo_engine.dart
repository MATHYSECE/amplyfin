import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/media_track.dart';
import '../models/player_message.dart';
import '../models/srt_subtitles.dart';
import 'video_engine.dart';

/// Moteur vidéo ExoPlayer, le lecteur d'Android (paquet officiel
/// video_player) : celui de Plex, Netflix ou YouTube. La puce décode et
/// remet l'image à Flutter (texture) : c'est ce qui lit proprement les 4K
/// que mpv abîmait sur la Fire TV.
/// Pas de vue native superposée (« platformView ») : sur la Fire TV,
/// Flutter ne rafraîchit plus ce qu'il dessine à côté de la vidéo (barre
/// figée sous un film au format cinéma).
class ExoEngine implements VideoEngine {
  /// Vidéo en cours (une nouvelle à chaque ouverture).
  final _current = ValueNotifier<VideoPlayerController?>(null);

  /// Vidéo en cours, pour un moteur qui reprend celui-ci (libmdk).
  @protected
  VideoPlayerController? get controller => _current.value;

  /// Réglages propres au moteur, une fois la vidéo ouverte (avant la
  /// lecture). Rien pour ExoPlayer.
  @protected
  void prepare(VideoPlayerController controller) {}

  final _position = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _subtitle = StreamController<List<String>>.broadcast();
  final _errors = StreamController<EngineError>.broadcast();

  /// Dernier état transmis : on ne prévient que des changements.
  bool _wasPlaying = false;
  bool _wasBuffering = false;
  bool _wasCompleted = false;
  String? _lastError;

  /// Volume demandé (appliqué aussi aux vidéos ouvertes ensuite).
  double _volume = 1;

  /// Vrai une fois le moteur libéré (plus rien n'est transmis).
  bool _disposed = false;

  /// En-têtes de connexion de la vidéo en cours (aussi pour les
  /// sous-titres, sur le même serveur).
  Map<String, String> _headers = const {};

  /// Sous-titres en cours (null : aucun), et lignes affichées.
  SrtSubtitles? _srt;
  List<String> _lines = const [];

  /// Numéro de la demande de sous-titres : une réponse arrivée après un
  /// autre choix est ignorée.
  int _subtitleRequest = 0;

  @override
  late final EngineStreams stream = EngineStreams(
    position: _position.stream,
    playing: _playing.stream,
    buffering: _buffering.stream,
    completed: _completed.stream,
    subtitle: _subtitle.stream,
    errors: _errors.stream,
    // ExoPlayer signale tout problème d'image comme une erreur
    decodeFailures: const Stream.empty(),
  );

  @override
  EngineState get state {
    final value = _current.value?.value;
    if (value == null) return const EngineState();
    return EngineState(
      position: value.position,
      duration: value.duration,
      buffer: value.buffered.isEmpty ? Duration.zero : value.buffered.last.end,
      playing: value.isPlaying,
      buffering: value.isBuffering,
      subtitle: _lines,
    );
  }

  /// ExoPlayer passe toujours par les décodeurs d'Android (la puce pour la
  /// vidéo) : il ne dit pas lequel, seulement la taille de l'image.
  @override
  Future<List<String>> playbackDetails() async {
    final value = _current.value?.value;
    return [
      'Lecteur : ExoPlayer (Android)',
      if (value != null && !value.size.isEmpty)
        'Image : ${value.size.width.round()} × ${value.size.height.round()}',
    ];
  }

  @override
  Future<void> initialize({required double refreshRate}) async {
    // Rien à préparer : l'affichage est créé avec chaque vidéo
  }

  @override
  Widget buildVideo({bool fill = false}) =>
      ValueListenableBuilder<VideoPlayerController?>(
        valueListenable: _current,
        builder: (context, controller, _) {
          if (controller == null) return const SizedBox.shrink();
          // Redessinée quand la taille de l'image est connue
          return ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (!value.isInitialized || value.size.isEmpty) {
                return const SizedBox.shrink();
              }
              if (fill) {
                return ClipRect(
                  child: SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox.fromSize(
                        size: value.size,
                        child: VideoPlayer(controller),
                      ),
                    ),
                  ),
                );
              }
              return Center(
                child: AspectRatio(
                  aspectRatio: value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              );
            },
          );
        },
      );

  @override
  Future<void> open(EngineMedia media) async {
    await _release();
    _headers = media.headers;
    final uri = Uri.tryParse(media.uri);
    // Fichier téléchargé (chemin) ou adresse du serveur
    final controller = uri == null || !uri.hasScheme
        ? VideoPlayerController.file(
            File(media.uri),
            viewType: VideoViewType.textureView,
          )
        : VideoPlayerController.networkUrl(
            uri,
            httpHeaders: media.headers,
            viewType: VideoViewType.textureView,
          );
    controller.addListener(() => _onChange(controller));
    _current.value = controller;
    try {
      await controller.initialize();
      if (_current.value != controller) return;
      prepare(controller);
      await controller.setVolume(_volume);
      if (media.start > Duration.zero) await controller.seekTo(media.start);
      await controller.play();
    } on Object catch (e) {
      // Fichier illisible, serveur injoignable… : le lecteur décide
      if (!_disposed && _current.value == controller) _report('$e');
    }
  }

  /// Transmet les changements de la vidéo [controller] (si c'est toujours
  /// celle en cours).
  void _onChange(VideoPlayerController controller) {
    if (_disposed || _current.value != controller) return;
    final value = controller.value;
    _position.add(value.position);
    _showSubtitlesAt(value.position);
    if (value.isPlaying != _wasPlaying) {
      _wasPlaying = value.isPlaying;
      _playing.add(value.isPlaying);
      _keepScreenOn(value.isPlaying);
    }
    if (value.isBuffering != _wasBuffering) {
      _wasBuffering = value.isBuffering;
      _buffering.add(value.isBuffering);
    }
    if (value.isCompleted != _wasCompleted) {
      _wasCompleted = value.isCompleted;
      _completed.add(value.isCompleted);
    }
    final error = value.errorDescription;
    if (error != null && error != _lastError) _report(error);
  }

  /// Écran gardé allumé pendant la lecture (sinon la télé ou le téléphone
  /// se met en veille en plein film), relâché en pause. mpv le fait seul ;
  /// ExoPlayer non.
  void _keepScreenOn(bool on) {
    unawaited(
      (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((_) {}),
    );
  }

  /// Erreur de lecture, sans adresse ni clé de connexion.
  void _report(String message) {
    _lastError = message;
    _errors.add(EngineError(detail: cleanPlayerMessage(message)));
  }

  @override
  Future<void> waitForTracks() async {
    // Les pistes sont connues dès l'ouverture
  }

  /// ExoPlayer liste les pistes audio du fichier dans l'ordre du fichier,
  /// comme mpv : la n-ième piste audio du serveur est la n-ième ici.
  @override
  Future<void> selectAudio(List<MediaTrack> all, MediaTrack track) async {
    final controller = _current.value;
    if (controller == null || !controller.isAudioTrackSupportAvailable()) {
      return;
    }
    final number = playerTrackId(all, track);
    final tracks = await controller.getAudioTracks();
    if (number == null || number > tracks.length) return;
    final chosen = tracks[number - 1];
    if (!chosen.isSelected) await controller.selectAudioTrack(chosen.id);
  }

  /// Seuls les sous-titres à part (SRT envoyé par le serveur) sont
  /// affichés : ExoPlayer ne donne pas ceux du fichier.
  @override
  Future<void> selectSubtitles(SubtitleSource source) async {
    final request = ++_subtitleRequest;
    _srt = null;
    _showSubtitlesAt(state.position);
    if (source is! ExternalSubtitles) return;
    try {
      final srt = SrtSubtitles.parse(
        utf8.decode(await _readSubtitles(source.url), allowMalformed: true),
      );
      if (_disposed || request != _subtitleRequest) return;
      _srt = srt;
      _showSubtitlesAt(state.position);
    } on Object catch (e) {
      // Le lecteur réessaie un peu plus tard (serveur occupé)
      if (_disposed || request != _subtitleRequest) return;
      if (kDebugMode) debugPrint('Sous-titres : $e');
      _errors.add(
        EngineError(detail: cleanPlayerMessage('$e'), subtitles: true),
      );
    }
  }

  /// Contenu d'un fichier de sous-titres : sur le téléphone (vidéo
  /// téléchargée, « file:// ») ou sur le serveur.
  Future<List<int>> _readSubtitles(String url) async {
    final uri = Uri.parse(url);
    if (uri.isScheme('file')) return File(uri.toFilePath()).readAsBytes();
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException('Sous-titres : erreur ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  /// Met à jour les lignes affichées pour la position [position].
  void _showSubtitlesAt(Duration position) {
    final lines = _srt?.linesAt(position) ?? const <String>[];
    if (listEquals(lines, _lines)) return;
    _lines = lines;
    _subtitle.add(lines);
  }

  @override
  Future<void> play() async => _current.value?.play();

  @override
  Future<void> pause() async => _current.value?.pause();

  @override
  Future<void> playOrPause() async {
    final controller = _current.value;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  @override
  Future<void> seek(Duration position) async =>
      _current.value?.seekTo(position);

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _current.value?.setVolume(_volume);
  }

  @override
  Future<void> stop() => _release();

  /// Libère la vidéo en cours et remet l'état à zéro.
  Future<void> _release() async {
    final controller = _current.value;
    _current.value = null;
    if (_wasPlaying) _keepScreenOn(false);
    _wasPlaying = false;
    _wasBuffering = false;
    _wasCompleted = false;
    _lastError = null;
    // Les sous-titres sont choisis à nouveau pour chaque vidéo
    _subtitleRequest++;
    _srt = null;
    _showSubtitlesAt(Duration.zero);
    await controller?.dispose();
  }

  /// Appelé pendant la fermeture de l'écran : aucun widget ne doit être
  /// prévenu (l'arbre est verrouillé), on libère donc sans rien annoncer.
  @override
  Future<void> dispose() async {
    _disposed = true;
    _keepScreenOn(false);
    final controller = _current.value;
    _current.dispose();
    await controller?.dispose();
    for (final controller in [
      _position,
      _playing,
      _buffering,
      _completed,
      _subtitle,
      _errors,
    ]) {
      await controller.close();
    }
  }
}
