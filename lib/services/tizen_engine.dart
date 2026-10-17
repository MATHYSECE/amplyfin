import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
// Paquet à part : il ne se mélange pas avec video_player (ExoPlayer)
import 'package:video_player_videohole/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/media_track.dart';
import '../models/player_message.dart';
import '../models/srt_subtitles.dart';
import 'video_engine.dart';

/// Moteur vidéo des télés Samsung (Tizen) : le lecteur standard de la
/// télé (paquet video_player_videohole), décodé par sa puce. La vidéo est
/// dessinée par la télé derrière l'appli, qui lui laisse un « trou »
/// transparent à sa place (nos commandes restent par-dessus).
/// AVPlay, l'autre lecteur de Samsung, exige un certificat partenaire.
class TizenEngine implements VideoEngine {
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

  /// En-têtes de connexion de la vidéo en cours (pour les sous-titres).
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
    // Le lecteur de la télé signale tout problème comme une erreur
    decodeFailures: const Stream.empty(),
  );

  @override
  EngineState get state {
    final value = _current.value?.value;
    if (value == null) return const EngineState();
    final duration = value.duration.end;
    return EngineState(
      position: value.position,
      duration: duration,
      // Le lecteur donne un pourcentage chargé
      buffer: duration * (value.buffered.clamp(0, 100) / 100),
      playing: value.isPlaying,
      buffering: value.isBuffering,
      subtitle: _lines,
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
    _headers = media.headers;
    final controller = VideoPlayerController.network(
      withToken(media.uri, media.headers),
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

  /// Le lecteur de la télé n'envoie pas notre en-tête de connexion : le
  /// jeton passe dans l'adresse (`ApiKey`, toujours accepté par Jellyfin).
  @visibleForTesting
  static String withToken(String url, Map<String, String> headers) {
    final header = headers['Authorization'];
    final match = header == null
        ? null
        : RegExp(r'Token="([^"]*)"').firstMatch(header);
    final uri = Uri.tryParse(url);
    if (match == null || uri == null) return url;
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'ApiKey': Uri.decodeComponent(match.group(1)!),
          },
        )
        .toString();
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

  /// Écran gardé allumé pendant la lecture (sinon la télé se met en veille
  /// en plein film), relâché en pause.
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

  /// La télé liste les pistes audio dans l'ordre du fichier (vérifié sur
  /// la télé) : la n-ième piste audio du serveur est la n-ième ici.
  @override
  Future<void> selectAudio(List<MediaTrack> all, MediaTrack track) async {
    final controller = _current.value;
    if (controller == null) return;
    final number = playerTrackId(all, track);
    final tracks = await controller.audioTracks ?? const <AudioTrack>[];
    if (number == null || number > tracks.length) return;
    await controller.setTrackSelection(tracks[number - 1]);
  }

  /// Seuls les sous-titres à part (SRT envoyé par le serveur) sont
  /// affichés, par l'appli.
  @override
  Future<void> selectSubtitles(SubtitleSource source) async {
    final request = ++_subtitleRequest;
    _srt = null;
    _showSubtitlesAt(state.position);
    if (source is! ExternalSubtitles) return;
    try {
      final response = await http
          .get(Uri.parse(source.url), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw HttpException('Sous-titres : erreur ${response.statusCode}');
      }
      final srt = SrtSubtitles.parse(
        utf8.decode(response.bodyBytes, allowMalformed: true),
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

  /// La télé avance jusqu'à l'image-clé la plus proche (pas à la seconde
  /// près).
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
