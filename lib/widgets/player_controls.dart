import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../models/durations.dart';
import '../services/device_capabilities.dart';
import '../theme/app_theme.dart';
import 'tv_focus.dart';
import 'ui.dart';

/// Ce qu'on règle en glissant le doigt de haut en bas.
enum _Level { brightness, volume }

/// Commandes du lecteur, dessinées par l'appli (au lieu de celles de
/// media_kit) :
/// - un appui affiche ou masque les commandes (masquées seules après 3 s) ;
/// - double appui à gauche / à droite : recule / avance de 10 s ;
/// - glisser de haut en bas sur la moitié gauche : luminosité,
///   sur la moitié droite : volume du téléphone.
///
/// Sur une télé, à la télécommande :
/// - commandes masquées : OK = lecture / pause, gauche / droite = recule /
///   avance (10 s, puis 30 s en maintenant la touche), haut / bas / Menu =
///   affiche les commandes ;
/// - commandes affichées : les flèches passent d'un bouton à l'autre ;
/// - Retour cache les commandes ([PlayerControlsState.handleBack]) ;
/// - les touches lecture / pause / avance / retour rapide marchent toujours.
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.title,
    required this.subtitle,
    required this.sourceLabel,
    required this.onBack,
    required this.onAudio,
    required this.onSubtitles,
    required this.onQuality,
    this.onVisibleChanged,
    this.onKeyActivity,
    this.onSelectOverride,
  });

  final Player player;

  /// Titre en gras (le film, ou la série).
  final String title;

  /// Petite ligne sous le titre (ex. « S1 · É3 · Titre »), facultative.
  final String? subtitle;

  /// Mention ORIGINAL / CONVERTI / CONVERSION… (null : rien).
  final ValueListenable<String?> sourceLabel;

  final VoidCallback onBack;

  /// Menus Audio, Sous-titres et Qualité (terminés quand le menu se ferme).
  final Future<void> Function() onAudio;
  final Future<void> Function() onSubtitles;
  final Future<void> Function() onQuality;

  /// Prévenu quand les commandes s'affichent ou se masquent
  /// (les sous-titres remontent au-dessus de la barre de progression).
  final ValueChanged<bool>? onVisibleChanged;

  /// Télé : une touche de la télécommande a été pressée (on regarde bien).
  final VoidCallback? onKeyActivity;

  /// Télé, commandes masquées : OK d'abord proposé ici (ex. « Passer
  /// l'intro » affiché) ; renvoie vrai s'il a servi.
  final bool Function()? onSelectOverride;

  @override
  State<PlayerControls> createState() => PlayerControlsState();
}

class PlayerControlsState extends State<PlayerControls> {
  static const _hideDelay = Duration(seconds: 3);
  static const _seekStep = Duration(seconds: 10);

  Player get _player => widget.player;

  bool _visible = true;
  Timer? _hideTimer;
  StreamSubscription<bool>? _playingSubscription;

  // Luminosité et volume (de 0 à 1), et la jauge affichée pendant le réglage
  double _brightness = 0.5;
  double _volume = 0.5;
  _Level? _level;
  Timer? _levelTimer;

  // Retour visuel du double appui : -1 recul, 1 avance, 0 rien
  int _seekFeedback = 0;
  Timer? _seekFeedbackTimer;
  Offset? _doubleTapPosition;

  // Télé : le lecteur reçoit les touches quand les commandes sont masquées,
  // le bouton lecture / pause est sélectionné quand elles s'affichent
  final _rootFocus = FocusNode(debugLabel: 'Lecteur');
  final _playFocus = FocusNode(debugLabel: 'Lecture / pause');
  bool get _tv => DeviceCapabilities.isTv;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
    // En pause, les commandes restent affichées
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (playing) {
        _scheduleHide();
      } else {
        _hideTimer?.cancel();
        if (mounted) _setVisible(true);
      }
    });
    // Télé : pas de luminosité ni de volume à régler (la télé les gère)
    if (!_tv) _readLevels();
  }

  /// Lit la luminosité et le volume actuels (point de départ des réglages).
  Future<void> _readLevels() async {
    // Pas de fenêtre de volume d'Android par-dessus la vidéo
    VolumeController.instance.showSystemUI = false;
    try {
      _brightness = await ScreenBrightness.instance.application;
      _volume = await VolumeController.instance.getVolume();
    } on Exception {
      // Réglage indisponible sur cet appareil : on part du milieu
    }
    // Le volume peut aussi changer avec les boutons du téléphone
    VolumeController.instance.addListener(
      (volume) => _volume = volume,
      fetchInitialVolume: false,
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _levelTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _playingSubscription?.cancel();
    _rootFocus.dispose();
    _playFocus.dispose();
    if (_tv) {
      super.dispose();
      return;
    }
    VolumeController.instance.removeListener();
    VolumeController.instance.showSystemUI = true;
    // On rend au téléphone sa luminosité habituelle
    ScreenBrightness.instance.resetApplicationScreenBrightness().catchError(
      (Object _) {},
    );
    super.dispose();
  }

  /// Vrai pendant qu'un menu (audio, sous-titres, qualité) est ouvert : les
  /// commandes restent affichées dessous.
  bool _menuOpen = false;

  /// Ouvre un menu ; à sa fermeture, les commandes restent un moment.
  Future<void> _openMenu(Future<void> Function() open) async {
    _hideTimer?.cancel();
    _menuOpen = true;
    try {
      await open();
    } finally {
      _menuOpen = false;
      if (mounted) _interacted();
    }
  }

  /// Relance le compte à rebours avant de masquer les commandes.
  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_player.state.playing || _menuOpen) return;
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) _setVisible(false);
    });
  }

  /// Affiche ou masque les commandes, et prévient le lecteur.
  void _setVisible(bool visible) {
    if (_visible == visible) return;
    // Télé : en masquant, le lecteur reprend les touches (seulement si la
    // sélection était sur ses boutons, pas dans un menu ou une fenêtre)
    if (_tv && !visible && _rootFocus.hasFocus) _rootFocus.requestFocus();
    setState(() => _visible = visible);
    widget.onVisibleChanged?.call(visible);
  }

  /// Télé : affiche les commandes, bouton lecture / pause sélectionné.
  void _showWithFocus() {
    _setVisible(true);
    _scheduleHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playFocus.requestFocus();
    });
  }

  /// Télé : le lecteur reprend les touches (ex. après la disparition du
  /// bouton « Passer l'intro » qui était sélectionné).
  void takeFocus() {
    if (_tv && !_visible) _rootFocus.requestFocus();
  }

  /// Télé : bouton Retour. Commandes affichées : on les masque (et le
  /// lecteur reste ouvert) ; renvoie faux si elles l'étaient déjà.
  bool handleBack() {
    if (!_tv || !_visible) return false;
    _hideTimer?.cancel();
    _setVisible(false);
    return true;
  }

  /// Télé : touches de la télécommande.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    widget.onKeyActivity?.call();
    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;

    // Touches de lecture : toujours
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      if (!repeat) _playOrPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.mediaRewind) {
      _seekWithFeedback(
        key == LogicalKeyboardKey.mediaFastForward ? 1 : -1,
        repeat: repeat,
      );
      return KeyEventResult.handled;
    }

    // Commandes affichées : les flèches et OK vont aux boutons
    if (_visible) {
      _scheduleHide();
      return KeyEventResult.ignored;
    }

    // Commandes masquées
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (!repeat && !(widget.onSelectOverride?.call() ?? false)) {
        _player.playOrPause();
        _showWithFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _seekWithFeedback(
        key == LogicalKeyboardKey.arrowRight ? 1 : -1,
        repeat: repeat,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.contextMenu) {
      if (!repeat) _showWithFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Télé : recule ou avance ([direction] -1 / 1) de 10 s, ou de 30 s quand
  /// la touche reste enfoncée, avec la bulle « +10 s · 12:34 ».
  void _seekWithFeedback(int direction, {required bool repeat}) {
    final step = Duration(seconds: repeat ? 30 : 10);
    _seekBy(direction > 0 ? step : -step);
    _showSeekFeedback(direction, seconds: step.inSeconds);
  }

  void _toggleVisible() {
    _setVisible(!_visible);
    if (_visible) _scheduleHide();
  }

  /// Toute action sur une commande garde les commandes affichées un moment.
  void _interacted() {
    _setVisible(true);
    _scheduleHide();
  }

  void _seekBy(Duration step) {
    final duration = _player.state.duration;
    var target = _player.state.position + step;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    _player.seek(target);
  }

  void _playOrPause() {
    _player.playOrPause();
    _interacted();
  }

  // ---------- Double appui ----------

  void _onDoubleTap(double width) {
    final x = _doubleTapPosition?.dx ?? width / 2;
    if (x < width * 0.4) {
      _seekBy(-_seekStep);
      _showSeekFeedback(-1);
    } else if (x > width * 0.6) {
      _seekBy(_seekStep);
      _showSeekFeedback(1);
    } else {
      _playOrPause();
    }
  }

  /// Durée du dernier saut (pour la bulle) et position visée.
  int _seekSeconds = 10;

  void _showSeekFeedback(int direction, {int seconds = 10}) {
    setState(() {
      _seekFeedback = direction;
      _seekSeconds = seconds;
    });
    _seekFeedbackTimer?.cancel();
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _seekFeedback = 0);
    });
  }

  // ---------- Luminosité et volume ----------

  void _onLevelDragStart(DragStartDetails details, double width) {
    _levelTimer?.cancel();
    setState(() {
      _level = details.localPosition.dx < width / 2
          ? _Level.brightness
          : _Level.volume;
    });
  }

  void _onLevelDragUpdate(DragUpdateDetails details, double height) {
    // Glisser sur 70 % de la hauteur de l'écran = de 0 à 100 %
    final change = -details.delta.dy / (height * 0.7);
    setState(() {
      if (_level == _Level.brightness) {
        _brightness = (_brightness + change).clamp(0.0, 1.0);
        ScreenBrightness.instance
            .setApplicationScreenBrightness(_brightness)
            .catchError((Object _) {});
      } else {
        _volume = (_volume + change).clamp(0.0, 1.0);
        VolumeController.instance.setVolume(_volume).catchError((Object _) {});
      }
    });
  }

  void _onLevelDragEnd(DragEndDetails _) {
    _levelTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _level = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controls = _buildLayout();
    if (!_tv) return controls;
    // Télé : le lecteur écoute la télécommande
    return Focus(
      focusNode: _rootFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: controls,
    );
  }

  /// Bulle du saut : « −10 s », et sur télé la position visée.
  String _seekLabel(int direction) {
    final sign = direction < 0 ? '−' : '+';
    final label = '$sign$_seekSeconds s';
    if (!_tv) return label;
    return '$label · ${formatPosition(_player.state.position)}';
  }

  Widget _buildLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Zone des gestes, sur toute la vidéo
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleVisible,
              onDoubleTapDown: (details) =>
                  _doubleTapPosition = details.localPosition,
              onDoubleTap: () => _onDoubleTap(width),
              onVerticalDragStart: (d) => _onLevelDragStart(d, width),
              onVerticalDragUpdate: (d) => _onLevelDragUpdate(d, height),
              onVerticalDragEnd: _onLevelDragEnd,
            ),
            // Commandes (en fondu)
            IgnorePointer(
              ignoring: !_visible,
              child: AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: AppDurations.medium,
                // Télé : boutons masqués impossibles à sélectionner
                child: ExcludeFocus(
                  excluding: _tv && !_visible,
                  child: _buildControls(context),
                ),
              ),
            ),
            // Jauges de luminosité (à gauche) et de volume (à droite)
            Positioned(
              left: 40,
              top: 0,
              bottom: 0,
              child: Center(
                child: _LevelGauge(
                  visible: _level == _Level.brightness,
                  value: _brightness,
                  icon: Icons.light_mode_outlined,
                  label: 'Luminosité',
                ),
              ),
            ),
            Positioned(
              right: 40,
              top: 0,
              bottom: 0,
              child: Center(
                child: _LevelGauge(
                  visible: _level == _Level.volume,
                  value: _volume,
                  icon: _volume == 0
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                  label: 'Volume',
                ),
              ),
            ),
            // Retour visuel du double appui
            Positioned(
              left: width * 0.12,
              top: 0,
              bottom: 0,
              child: Center(
                child: _SeekBubble(
                  visible: _seekFeedback < 0,
                  label: _seekLabel(-1),
                ),
              ),
            ),
            Positioned(
              right: width * 0.12,
              top: 0,
              bottom: 0,
              child: Center(
                child: _SeekBubble(
                  visible: _seekFeedback > 0,
                  label: _seekLabel(1),
                ),
              ),
            ),
            // Roue quand la vidéo charge (même commandes masquées)
            IgnorePointer(
              child: StreamBuilder<bool>(
                stream: _player.stream.buffering,
                initialData: _player.state.buffering,
                builder: (context, snapshot) => snapshot.data == true
                    ? const Center(
                        child: SizedBox(
                          width: 96,
                          height: 96,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subtitle = widget.subtitle;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Voile en haut et en bas : commandes lisibles sur n'importe quelle image
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.3, 0.62, 1],
                colors: [
                  AppColors.scrim70,
                  Colors.transparent,
                  Colors.transparent,
                  AppColors.scrim70,
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
            child: Column(
              children: [
                // Haut : retour, titre, mention, audio / sous-titres / qualité
                Row(
                  children: [
                    GlassCircleButton(
                      icon: Icons.chevron_left_rounded,
                      tooltip: 'Retour',
                      onPressed: widget.onBack,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    _SourceBadge(label: widget.sourceLabel),
                    const SizedBox(width: 12),
                    GlassCircleButton(
                      icon: Icons.volume_up_outlined,
                      tooltip: 'Audio',
                      onPressed: () => _openMenu(widget.onAudio),
                    ),
                    const SizedBox(width: 10),
                    GlassCircleButton(
                      icon: Icons.subtitles_outlined,
                      tooltip: 'Sous-titres',
                      onPressed: () => _openMenu(widget.onSubtitles),
                    ),
                    const SizedBox(width: 10),
                    GlassCircleButton(
                      icon: Icons.tune_rounded,
                      tooltip: 'Qualité',
                      onPressed: () => _openMenu(widget.onQuality),
                    ),
                  ],
                ),
                const Spacer(),
                // Centre : reculer, lecture / pause, avancer
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RoundButton(
                      icon: Icons.replay_10_rounded,
                      tooltip: 'Reculer de 10 secondes',
                      onPressed: () {
                        _seekBy(-_seekStep);
                        _interacted();
                      },
                    ),
                    const SizedBox(width: 44),
                    StreamBuilder<bool>(
                      stream: _player.stream.playing,
                      initialData: _player.state.playing,
                      builder: (context, snapshot) {
                        final playing = snapshot.data ?? false;
                        return _RoundButton(
                          icon: playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          tooltip: playing ? 'Pause' : 'Lecture',
                          size: 76,
                          filled: true,
                          focusNode: _playFocus,
                          onPressed: _playOrPause,
                        );
                      },
                    ),
                    const SizedBox(width: 44),
                    _RoundButton(
                      icon: Icons.forward_10_rounded,
                      tooltip: 'Avancer de 10 secondes',
                      onPressed: () {
                        _seekBy(_seekStep);
                        _interacted();
                      },
                    ),
                  ],
                ),
                const Spacer(),
                // Bas : barre de progression et temps (télé : avec les
                // boutons ±10 s plutôt que sélectionnable)
                ExcludeFocus(
                  excluding: _tv,
                  child: _SeekBar(player: _player, onInteraction: _interacted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Bouton rond du centre : blanc plein (lecture / pause) ou en verre.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 56,
    this.filled = false,
    this.focusNode,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final bool filled;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    // Télé : sélection ronde avec le contour blanc commun
    return TvFocusable(
      onTap: onPressed,
      focusNode: focusNode,
      radius: size / 2,
      scale: 1.12,
      child: _buildButton(),
    );
  }

  Widget _buildButton() {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? AppColors.white : AppColors.glassStrong,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          canRequestFocus: !DeviceCapabilities.isTv,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: size * 0.5,
              color: filled ? AppColors.black : AppColors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Mention « ORIGINAL » (lecture directe), « CONVERTI » (transcodage) ou
/// « CONVERSION… » (flux converti en préparation).
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label});

  final ValueListenable<String?> label;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: label,
      builder: (context, text, _) =>
          text == null ? const SizedBox.shrink() : OutlinePill(text),
    );
  }
}

/// Barre de progression : on peut la toucher ou la faire glisser pour se
/// déplacer dans la vidéo. En dessous, temps écoulé et temps restant.
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.player, required this.onInteraction});

  final Player player;
  final VoidCallback onInteraction;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  /// Position visée pendant un glissement (de 0 à 1), null sinon.
  double? _dragValue;

  Player get _player => widget.player;

  double _valueAt(double dx, double width) => (dx / width).clamp(0.0, 1.0);

  void _seekTo(double value) {
    final duration = _player.state.duration;
    if (duration > Duration.zero) _player.seek(duration * value);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return StreamBuilder<Duration>(
      stream: _player.stream.position,
      initialData: _player.state.position,
      builder: (context, snapshot) {
        final duration = _player.state.duration;
        final hasDuration = duration > Duration.zero;
        final position = snapshot.data ?? Duration.zero;
        final played =
            _dragValue ??
            (hasDuration
                ? position.inMilliseconds / duration.inMilliseconds
                : 0.0);
        final buffered = hasDuration
            ? _player.state.buffer.inMilliseconds / duration.inMilliseconds
            : 0.0;
        final shown = hasDuration
            ? duration * played.clamp(0.0, 1.0)
            : position;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final thumb = _dragValue == null ? 14.0 : 20.0;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    _seekTo(_valueAt(d.localPosition.dx, width));
                    widget.onInteraction();
                  },
                  onHorizontalDragStart: (d) => setState(
                    () => _dragValue = _valueAt(d.localPosition.dx, width),
                  ),
                  onHorizontalDragUpdate: (d) {
                    setState(
                      () => _dragValue = _valueAt(d.localPosition.dx, width),
                    );
                    widget.onInteraction();
                  },
                  onHorizontalDragEnd: (_) {
                    final value = _dragValue;
                    if (value != null) _seekTo(value);
                    setState(() => _dragValue = null);
                  },
                  child: SizedBox(
                    height: 30,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      clipBehavior: Clip.none,
                      children: [
                        _bar(width, 1, AppColors.track),
                        _bar(width, buffered, AppColors.trackBuffer),
                        _bar(width, played, AppColors.white),
                        Positioned(
                          left: width * played.clamp(0.0, 1.0) - thumb / 2,
                          child: AnimatedContainer(
                            duration: AppDurations.fast,
                            width: thumb,
                            height: thumb,
                            decoration: const BoxDecoration(
                              color: AppColors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.scrim55,
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatPosition(shown), style: textTheme.labelMedium),
                Text(
                  hasDuration ? '−${formatPosition(duration - shown)}' : '',
                  style: textTheme.labelMedium,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Un morceau de barre, de [fraction] de la largeur.
  Widget _bar(double width, double fraction, Color color) {
    return Container(
      width: width * fraction.clamp(0.0, 1.0),
      height: 5,
      decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
    );
  }
}

/// Jauge verticale (luminosité ou volume), visible pendant le réglage.
class _LevelGauge extends StatelessWidget {
  const _LevelGauge({
    required this.visible,
    required this.value,
    required this.icon,
    required this.label,
  });

  final bool visible;
  final double value;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppDurations.fast,
        child: Semantics(
          label: '$label ${(value * 100).round()} %',
          child: Container(
            width: 48,
            height: 176,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const ShapeDecoration(
              color: AppColors.scrim35,
              shape: StadiumBorder(
                side: BorderSide(color: AppColors.glassBorder),
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 6,
                    alignment: Alignment.bottomCenter,
                    decoration: const ShapeDecoration(
                      color: AppColors.track,
                      shape: StadiumBorder(),
                    ),
                    child: FractionallySizedBox(
                      heightFactor: value.clamp(0.0, 1.0),
                      child: const DecoratedBox(
                        decoration: ShapeDecoration(
                          color: AppColors.white,
                          shape: StadiumBorder(),
                        ),
                        child: SizedBox(width: 6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Icon(icon, size: 20, color: AppColors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bulle « −10 s » / « +10 s » après un double appui.
class _SeekBubble extends StatelessWidget {
  const _SeekBubble({required this.visible, required this.label});

  final bool visible;
  final String label;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppDurations.fast,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: const ShapeDecoration(
            color: AppColors.scrim55,
            shape: StadiumBorder(
              side: BorderSide(color: AppColors.glassBorder),
            ),
          ),
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
      ),
    );
  }
}
