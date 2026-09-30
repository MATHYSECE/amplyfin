import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api/jellyfin_api.dart';
import '../models/movie.dart';
import '../models/playback_info.dart';
import '../models/playback_quality.dart';
import '../models/session.dart';

/// Lecteur vidéo plein écran, à l'horizontale.
/// Par défaut le fichier original est lu tel quel (lecture directe) ;
/// le menu « Qualité » permet de demander un flux converti plus léger.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.api,
    required this.session,
    required this.movie,
  });

  final JellyfinApi api;
  final Session session;
  final Movie movie;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  /// Fréquence des signalements de position au serveur.
  static const _progressInterval = Duration(seconds: 10);

  /// Mémoire tampon du lecteur : 64 Mo, confortable pour de la 4K.
  static const _bufferSize = 64 * 1024 * 1024;

  final _player = Player(
    configuration: const PlayerConfiguration(
      bufferSize: _bufferSize,
      // En développement : messages détaillés du moteur vidéo
      logLevel: kDebugMode ? MPVLogLevel.info : MPVLogLevel.error,
    ),
  );

  /// Affichage de la vidéo (créé au démarrage, selon l'appareil).
  VideoController? _controller;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _progressTimer;

  /// Séance de lecture en cours (null tant que la vidéo n'est pas ouverte).
  /// ValueNotifier : les commandes de media_kit ne se redessinent pas seules,
  /// la mention ORIGINAL / CONVERTI écoute donc directement cette valeur.
  final _info = ValueNotifier<PlaybackInfo?>(null);
  PlaybackQuality _quality = PlaybackQuality.original;
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
    if (kDebugMode) {
      // Affiche les messages du moteur vidéo dans la console (diagnostic)
      _subscriptions.add(
        _player.stream.log.listen(
          (log) => debugPrint('mpv ${log.level} [${log.prefix}] ${log.text}'),
        ),
      );
    }
    _progressTimer = Timer.periodic(
      _progressInterval,
      (_) => _reportProgress(),
    );
    _start();
  }

  /// Prépare l'affichage puis lance le film.
  Future<void> _start() async {
    final controller = VideoController(
      _player,
      configuration: await _videoConfiguration(),
    );
    if (!mounted) return;
    setState(() => _controller = controller);
    await _open(PlaybackQuality.original);
  }

  /// Réglage de l'affichage vidéo. Sur l'émulateur Android, l'affichage
  /// OpenGL habituel de media_kit ne fonctionne pas (écran noir) : on envoie
  /// alors l'image décodée par Android directement à l'écran.
  static Future<VideoControllerConfiguration> _videoConfiguration() async {
    if (Platform.isAndroid) {
      final device = await DeviceInfoPlugin().androidInfo;
      if (!device.isPhysicalDevice) {
        return const VideoControllerConfiguration(
          vo: 'mediacodec_embed',
          hwdec: 'mediacodec',
        );
      }
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
  Future<void> _open(
    PlaybackQuality quality, {
    Duration start = Duration.zero,
  }) async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final info = await widget.api.getPlaybackInfo(
        userId: widget.session.userId,
        itemId: widget.movie.id,
        quality: quality,
        start: start,
      );
      if (!mounted) return;

      // Changement de qualité : l'ancienne séance est terminée
      final previous = _info.value;
      if (previous != null) {
        _report(() => widget.api.reportPlaybackStopped(previous, start));
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
      setState(() => _quality = quality);
      _report(() => widget.api.reportPlaybackStart(info, start));
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Erreur signalée par le lecteur lui-même (fichier illisible, coupure…).
  void _onPlayerError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Problème de lecture : $message')));
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

  /// Menu « Qualité » : choisir une qualité relance la vidéo au même endroit.
  Future<void> _chooseQuality() async {
    final chosen = await showModalBottomSheet<PlaybackQuality>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                'Qualité',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final quality in PlaybackQuality.all)
              ListTile(
                title: Text(quality.label),
                subtitle: Text(
                  quality.isOriginal
                      ? 'Fichier lu tel quel, sans conversion'
                      : 'Converti par le serveur',
                ),
                trailing: quality == _quality ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(quality),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == _quality || !mounted) return;
    await _open(chosen, start: _player.state.position);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final controller = _controller;

    // Commandes toutes prêtes de media_kit (personnalisées à l'étape design)
    final controlsTheme = MaterialVideoControlsThemeData(
      seekOnDoubleTap: true,
      seekBarPositionColor: colors.primary,
      seekBarThumbColor: colors.primary,
      topButtonBar: [
        MaterialCustomButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            widget.movie.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        _SourceLabel(info: _info),
        const SizedBox(width: 8),
        MaterialCustomButton(
          icon: const Icon(Icons.high_quality_outlined),
          onPressed: _chooseQuality,
        ),
      ],
      bottomButtonBar: const [MaterialPositionIndicator(), Spacer()],
    );

    return Scaffold(
      body: Stack(
        children: [
          if (controller != null)
            MaterialVideoControlsTheme(
              normal: controlsTheme,
              fullscreen: controlsTheme,
              child: Video(
                controller: controller,
                controls: MaterialVideoControls,
              ),
            ),
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

/// Petite mention « ORIGINAL » (lecture directe) ou « CONVERTI » (transcodage).
/// Rien tant que la vidéo n'est pas ouverte.
class _SourceLabel extends StatelessWidget {
  const _SourceLabel({required this.info});

  final ValueListenable<PlaybackInfo?> info;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: info,
      builder: (context, info, _) => info == null
          ? const SizedBox.shrink()
          : _buildLabel(context, info.directPlay),
    );
  }

  Widget _buildLabel(BuildContext context, bool directPlay) {
    final colors = Theme.of(context).colorScheme;
    return Text(
      directPlay ? 'ORIGINAL' : 'CONVERTI',
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: directPlay ? colors.primary : colors.tertiary),
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
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: onBack, child: const Text('Retour')),
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
