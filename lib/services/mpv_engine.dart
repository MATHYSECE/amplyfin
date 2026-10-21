import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/media_track.dart';
import '../models/player_message.dart';
import 'video_engine.dart';

/// Moteur vidéo mpv (paquet media_kit) : iPhone, iPad, PC… et Android pour
/// l'instant.
class MpvEngine implements VideoEngine {
  /// Mémoire tampon du lecteur : 64 Mo, confortable pour de la 4K.
  static const _bufferSize = 64 * 1024 * 1024;

  final _player = Player(
    configuration: const PlayerConfiguration(
      bufferSize: _bufferSize,
      // En développement : messages détaillés du moteur vidéo
      logLevel: kDebugMode ? MPVLogLevel.info : MPVLogLevel.error,
    ),
  );

  /// Affichage de la vidéo (créé par initialize, selon l'appareil).
  VideoController? _controller;

  @override
  late final EngineStreams stream = EngineStreams(
    position: _player.stream.position,
    playing: _player.stream.playing,
    buffering: _player.stream.buffering,
    completed: _player.stream.completed,
    subtitle: _player.stream.subtitle,
    errors: _player.stream.error
        .map(_sortError)
        .where((error) => error != null)
        .cast<EngineError>(),
    decodeFailures: _player.stream.log.where(_isDecodeFailure),
  );

  @override
  EngineState get state {
    final state = _player.state;
    return EngineState(
      position: state.position,
      duration: state.duration,
      buffer: state.buffer,
      playing: state.playing,
      buffering: state.buffering,
      subtitle: state.subtitle,
    );
  }

  @override
  Future<void> initialize({required double refreshRate}) async {
    _controller = VideoController(
      _player,
      configuration: _videoConfiguration(),
    );
    await _saveEnergy();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _smoothMotion(refreshRate);
    }
  }

  /// Dessin de l'image le plus léger possible (batterie) : mise à l'échelle
  /// simple, sans traitements que l'œil ne voit presque pas sur un écran de
  /// téléphone ou de portable (lissage des dégradés, mesure de la
  /// luminosité HDR à chaque image…).
  /// iPhone : la puce vidéo décode, 10 bits compris ; elle remet l'image en
  /// 8 bits (nv12), le seul format qu'elle sait passer directement à
  /// l'affichage de media_kit (sinon mpv décoderait avec le processeur).
  Future<void> _saveEnergy() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final settings = {
      'scale': 'bilinear',
      'dscale': 'bilinear',
      'cscale': 'bilinear',
      'dither-depth': 'no',
      'correct-downscaling': 'no',
      'linear-downscaling': 'no',
      'sigmoid-upscaling': 'no',
      'deband': 'no',
      'hdr-compute-peak': 'no',
      if (defaultTargetPlatform == TargetPlatform.iOS) ...{
        'hwdec-image-format': 'nv12',
        // Ancien nom du même réglage (versions précédentes de mpv)
        'videotoolbox-format': 'nv12',
      },
    };
    for (final MapEntry(:key, :value) in settings.entries) {
      try {
        await platform.setProperty(key, value);
      } on Object {
        // Réglage inconnu de cette version de mpv : on continue
      }
    }
  }

  @override
  Future<List<String>> playbackDetails() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return const ['Lecteur : mpv'];
    Future<String> read(String name) async {
      try {
        return await platform.getProperty(name);
      } on Object {
        return '';
      }
    }

    final hwdec = await read('hwdec-current');
    final codec = await read('video-codec');
    final format = await read('video-params/pixelformat');
    final width = await read('video-params/w');
    final height = await read('video-params/h');
    final fps = double.tryParse(await read('estimated-vf-fps'));
    final dropped = await read('frame-drop-count');
    final decoderDropped = await read('decoder-frame-drop-count');
    final onChip = hwdec.isNotEmpty && hwdec != 'no';
    return [
      'Lecteur : mpv',
      'Décodage : ${onChip ? 'puce vidéo ($hwdec)' : 'processeur'}',
      if (codec.isNotEmpty) 'Vidéo : ${codec.split(' ').first}',
      if (width.isNotEmpty)
        'Image : $width × $height'
            '${format.isEmpty ? '' : ' · $format'}'
            '${fps == null ? '' : ' · ${fps.toStringAsFixed(fps % 1 == 0 ? 0 : 3)} i/s'}',
      'Images perdues : ${dropped.isEmpty ? 0 : dropped}'
          '${decoderDropped.isEmpty || decoderDropped == '0' ? '' : ' (décodeur : $decoderDropped)'}',
    ];
  }

  /// Réglage de l'affichage vidéo. Sur Android, la puce vidéo décode l'image
  /// et l'affiche elle-même à l'écran (comme les lecteurs natifs) : c'est le
  /// seul moyen de lire la HEVC 10 bits ou la 4K de façon fluide. Avec le
  /// réglage par défaut de media_kit, la puce n'a pas accès à l'écran et le
  /// processeur, trop lent, prend le relais (et l'émulateur reste noir).
  /// Sur Windows, la carte graphique décode (D3D11, sinon DXVA2) ; l'image
  /// est recopiée pour la fenêtre de l'appli (« d3d11va-copy »), ce qui
  /// suffit pour la 4K HEVC 10 bits.
  VideoControllerConfiguration _videoConfiguration() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const VideoControllerConfiguration(
        vo: 'mediacodec_embed',
        hwdec: 'mediacodec',
      );
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return const VideoControllerConfiguration(hwdec: 'd3d11va,dxva2,auto');
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Puce vidéo de l'iPhone / iPad (VideoToolbox) en priorité
      return const VideoControllerConfiguration(hwdec: 'videotoolbox,auto');
    }
    return const VideoControllerConfiguration();
  }

  /// Windows : un film à 24 images/s sur un écran à 60 Hz montre ses images
  /// tour à tour 3 puis 2 fois, d'où un mouvement saccadé. Le lecteur se
  /// cale sur l'écran et fond deux images voisines aux changements d'image.
  /// Il dessine dans la fenêtre de l'appli : on lui donne la fréquence de
  /// l'écran, qu'il ne connaît pas.
  Future<void> _smoothMotion(double refreshRate) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty(
        'display-fps-override',
        (refreshRate > 0 ? refreshRate : 60).toStringAsFixed(3),
      );
      await platform.setProperty('video-sync', 'display-resample');
      await platform.setProperty('interpolation', 'yes');
      await platform.setProperty('tscale', 'oversample');
    } on Object {
      // Réglage refusé : lecture normale, sans lissage
    }
  }

  @override
  Widget buildVideo() {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    // La vidéo seule (commandes et sous-titres de media_kit désactivés)
    return Video(
      controller: controller,
      controls: NoVideoControls,
      subtitleViewConfiguration: const SubtitleViewConfiguration(
        visible: false,
      ),
    );
  }

  /// Tri des erreurs de mpv. Il signale aussi des erreurs sans gravité :
  /// décodeur refusé (il essaie aussitôt une autre méthode) → ignorée.
  /// Jamais le message brut : il peut contenir l'adresse du serveur et la
  /// clé de connexion.
  EngineError? _sortError(String message) {
    if (message.contains('Could not open codec')) return null;
    return EngineError(
      detail: cleanPlayerMessage(message),
      subtitles: message.contains('/Subtitles/'),
    );
  }

  /// Message de mpv qui dit que l'image ne peut pas s'afficher.
  bool _isDecodeFailure(PlayerLog log) {
    if (kDebugMode) {
      // Messages du moteur vidéo dans la console (diagnostic)
      debugPrint('mpv ${log.level} [${log.prefix}] ${log.text}');
    }
    if (log.level != 'fatal' && log.level != 'error') return false;
    final text = log.text.toLowerCase();
    return text.contains('video chain') || text.contains('video_out');
  }

  @override
  Future<void> open(EngineMedia media) => _player.open(
    Media(media.uri, httpHeaders: media.headers, start: media.start),
  );

  @override
  Future<void> waitForTracks() async {
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

  @override
  Future<void> selectAudio(List<MediaTrack> all, MediaTrack track) async {
    final id = playerTrackId(all, track);
    if (id != null) await _player.setAudioTrack(AudioTrack('$id', null, null));
  }

  @override
  Future<void> selectSubtitles(SubtitleSource source) async {
    switch (source) {
      case NoSubtitles():
        await _player.setSubtitleTrack(SubtitleTrack.no());
      case AutoSubtitles():
        await _player.setSubtitleTrack(SubtitleTrack.auto());
      case ExternalSubtitles(:final url, :final title, :final language):
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(url, title: title, language: language),
        );
      case EmbeddedSubtitles(:final all, :final track):
        final id = playerTrackId(all, track);
        if (id != null) {
          await _player.setSubtitleTrack(SubtitleTrack('$id', null, null));
        }
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume * 100);

  @override
  Future<void> stop() => _player.stop();

  /// Arrête d'abord la lecture (le décodeur vidéo libère l'écran),
  /// puis libère le lecteur. Libérer directement peut bloquer l'appli.
  @override
  Future<void> dispose() async {
    await _player.stop();
    await _player.dispose();
  }
}
