import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../models/media_track.dart';
import '../models/player_message.dart';
import 'video_engine.dart';

/// Moteur vidéo ExoPlayer, le lecteur d'Android (paquet officiel
/// video_player) : celui de Plex, Netflix ou YouTube. La puce décode et
/// l'image va directement à l'écran par une vue native, sans passer par
/// Flutter : c'est ce qui lit proprement les 4K que mpv abîmait sur la
/// Fire TV.
class ExoEngine implements VideoEngine {
  /// Vidéo en cours (une nouvelle à chaque ouverture).
  final _current = ValueNotifier<VideoPlayerController?>(null);

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
    );
  }

  @override
  Future<void> initialize({required double refreshRate}) async {
    // Rien à préparer : l'affichage est créé avec chaque vidéo
  }

  @override
  Widget buildVideo() => ValueListenableBuilder<VideoPlayerController?>(
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
    final uri = Uri.tryParse(media.uri);
    // Fichier téléchargé (chemin) ou adresse du serveur
    final controller = uri == null || !uri.hasScheme
        ? VideoPlayerController.file(
            File(media.uri),
            viewType: VideoViewType.platformView,
          )
        : VideoPlayerController.networkUrl(
            uri,
            httpHeaders: media.headers,
            viewType: VideoViewType.platformView,
          );
    controller.addListener(() => _onChange(controller));
    _current.value = controller;
    try {
      await controller.initialize();
      if (_current.value != controller) return;
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
    if (value.isPlaying != _wasPlaying) {
      _wasPlaying = value.isPlaying;
      _playing.add(value.isPlaying);
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

  /// Erreur de lecture, sans adresse ni clé de connexion.
  void _report(String message) {
    _lastError = message;
    _errors.add(EngineError(detail: cleanPlayerMessage(message)));
  }

  @override
  Future<void> waitForTracks() async {
    // Les pistes sont connues dès l'ouverture
  }

  @override
  Future<void> selectAudio(List<MediaTrack> all, MediaTrack track) async {
    // Étape suivante : pour l'instant, la piste par défaut du fichier
  }

  @override
  Future<void> selectSubtitles(SubtitleSource source) async {
    // Étape suivante : pour l'instant, pas de sous-titres
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
    _wasPlaying = false;
    _wasBuffering = false;
    _wasCompleted = false;
    _lastError = null;
    await controller?.dispose();
  }

  /// Appelé pendant la fermeture de l'écran : aucun widget ne doit être
  /// prévenu (l'arbre est verrouillé), on libère donc sans rien annoncer.
  @override
  Future<void> dispose() async {
    _disposed = true;
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
