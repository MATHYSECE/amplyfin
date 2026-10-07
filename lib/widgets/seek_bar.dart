import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../models/durations.dart';
import '../theme/app_theme.dart';

/// Distance parcourue par le repère (en secondes de vidéo) quand une flèche
/// reste enfoncée [held] : lentement au début, puis de plus en plus vite
/// jusqu'à 1/5 de la vidéo par seconde, atteint au bout de 2 s.
/// Ex. film de 2 h : les 3/4 sont atteints en 5 s environ.
double tvSeekDistance(Duration held, Duration total) {
  const minSpeed = 20.0; // secondes de vidéo par seconde d'appui
  const ramp = 2.0; // secondes avant la vitesse maximale
  final maxSpeed = math.max(total.inSeconds / 5, 60.0);
  final t = held.inMilliseconds / 1000;
  // La vitesse grandit comme le carré du temps, puis reste au maximum
  double distance(double t) =>
      minSpeed * t + (maxSpeed - minSpeed) * t * t * t / (3 * ramp * ramp);
  if (t <= ramp) return distance(t);
  return distance(ramp) + maxSpeed * (t - ramp);
}

/// Télé : déplacement dans la vidéo avec les flèches. Un repère bouge sur
/// la barre (10 s par appui, de plus en plus vite en maintenant la flèche)
/// et la vidéo n'y saute qu'une fois : peu après le relâchement, ou tout
/// de suite avec [commit]. Évite de recharger la vidéo à chaque répétition.
class TvScrubber extends ChangeNotifier {
  TvScrubber({
    required this.position,
    required this.duration,
    required this.seek,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Position et durée actuelles de la vidéo.
  final Duration Function() position;
  final Duration Function() duration;

  /// Fait sauter la vidéo.
  final Future<void> Function(Duration) seek;

  final DateTime Function() _now;

  static const step = Duration(seconds: 10);

  /// Attente après le relâchement avant de sauter.
  static const commitDelay = Duration(milliseconds: 600);

  Duration? _target;
  DateTime? _holdStart;
  DateTime? _lastMove;
  Timer? _commitTimer;

  /// Position visée, ou null quand on ne se déplace pas.
  Duration? get target => _target;
  bool get pending => _target != null;

  /// Flèche encore enfoncée.
  bool get holding => _holdStart != null;

  /// Flèche enfoncée ([direction] -1 recule, 1 avance) : 10 s.
  void press(int direction) {
    _commitTimer?.cancel();
    _holdStart = _lastMove = _now();
    _moveBy(step * direction);
  }

  /// Flèche toujours enfoncée (répétition) : avance selon la durée d'appui.
  void hold(int direction) {
    final start = _holdStart;
    final last = _lastMove;
    if (start == null || last == null) return press(direction);
    final now = _now();
    _lastMove = now;
    final total = duration();
    final seconds =
        tvSeekDistance(now.difference(start), total) -
        tvSeekDistance(last.difference(start), total);
    _moveBy(Duration(milliseconds: (seconds * 1000 * direction).round()));
  }

  /// Flèche relâchée : la vidéo saute au repère un peu après.
  void release() {
    _holdStart = _lastMove = null;
    if (_target == null) return;
    _commitTimer?.cancel();
    _commitTimer = Timer(commitDelay, commit);
  }

  /// Saute au repère tout de suite.
  Future<void> commit() async {
    _commitTimer?.cancel();
    _holdStart = _lastMove = null;
    final target = _target;
    if (target == null) return;
    await seek(target);
    // Le repère reste affiché jusqu'au saut (sauf s'il a encore bougé, ou
    // si le lecteur s'est fermé entre-temps)
    if (!_disposed && _target == target) {
      _target = null;
      notifyListeners();
    }
  }

  void _moveBy(Duration change) {
    final total = duration();
    var target = (_target ?? position()) + change;
    if (target < Duration.zero) target = Duration.zero;
    if (total > Duration.zero && target > total) target = total;
    _target = target;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _commitTimer?.cancel();
    super.dispose();
  }
}

/// Barre de progression : on peut la toucher ou la faire glisser pour se
/// déplacer dans la vidéo. En dessous, temps écoulé et temps restant.
/// Télé : sélectionnable ([focusNode]) ; le repère de [scrubber] et le
/// temps visé s'affichent pendant le déplacement aux flèches.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.player,
    required this.onInteraction,
    this.focusNode,
    this.scrubber,
  });

  final Player player;
  final VoidCallback onInteraction;
  final FocusNode? focusNode;
  final TvScrubber? scrubber;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  /// Position visée pendant un glissement (de 0 à 1), null sinon.
  double? _dragValue;

  /// Télé : barre sélectionnée.
  bool _focused = false;

  Player get _player => widget.player;

  double _valueAt(double dx, double width) => (dx / width).clamp(0.0, 1.0);

  void _seekTo(double value) {
    final duration = _player.state.duration;
    if (duration > Duration.zero) _player.seek(duration * value);
  }

  @override
  Widget build(BuildContext context) {
    Widget positionBar() => StreamBuilder<Duration>(
      stream: _player.stream.position,
      initialData: _player.state.position,
      builder: (context, snapshot) =>
          _buildBar(context, snapshot.data ?? Duration.zero),
    );
    final scrubber = widget.scrubber;
    // Télé : redessinée aussi à chaque mouvement du repère
    final bar = scrubber == null
        ? positionBar()
        : ListenableBuilder(
            listenable: scrubber,
            builder: (context, _) => positionBar(),
          );
    final focusNode = widget.focusNode;
    if (focusNode == null) return bar;
    return Focus(
      focusNode: focusNode,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: bar,
    );
  }

  Widget _buildBar(BuildContext context, Duration position) {
    final textTheme = Theme.of(context).textTheme;
    final duration = _player.state.duration;
    final hasDuration = duration > Duration.zero;
    final target = widget.scrubber?.target;
    final played =
        _dragValue ??
        (hasDuration
            ? (target ?? position).inMilliseconds / duration.inMilliseconds
            : 0.0);
    final buffered = hasDuration
        ? _player.state.buffer.inMilliseconds / duration.inMilliseconds
        : 0.0;
    final shown = hasDuration ? duration * played.clamp(0.0, 1.0) : position;
    final large = _dragValue != null || _focused;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final x = width * played.clamp(0.0, 1.0);
            final thumb = _focused ? 24.0 : (large ? 20.0 : 14.0);
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
                      left: x - thumb / 2,
                      child: AnimatedContainer(
                        duration: AppDurations.fast,
                        width: thumb,
                        height: thumb,
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          shape: BoxShape.circle,
                          // Télé, sélectionnée : contour blanc séparé du rond
                          // par un fin cercle sombre, et halo (comme les
                          // autres éléments sélectionnés)
                          border: _focused
                              ? Border.all(color: AppColors.scrim55, width: 3)
                              : null,
                          boxShadow: _focused
                              ? const [
                                  BoxShadow(
                                    color: AppColors.white,
                                    spreadRadius: 3,
                                  ),
                                  BoxShadow(
                                    color: AppColors.glow,
                                    blurRadius: 24,
                                    spreadRadius: 8,
                                  ),
                                ]
                              : const [
                                  BoxShadow(
                                    color: AppColors.scrim55,
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                        ),
                      ),
                    ),
                    // Télé : temps visé au-dessus du repère
                    if (target != null)
                      Positioned(
                        left: x,
                        bottom: 34,
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, 0),
                          child: _TimeBubble(formatPosition(target)),
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
  }

  /// Un morceau de barre, de [fraction] de la largeur.
  Widget _bar(double width, double fraction, Color color) {
    return AnimatedContainer(
      duration: AppDurations.fast,
      width: width * fraction.clamp(0.0, 1.0),
      height: _focused ? 8 : 5,
      decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
    );
  }
}

/// Bulle du temps visé, au-dessus du repère.
class _TimeBubble extends StatelessWidget {
  const _TimeBubble(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const ShapeDecoration(
        color: AppColors.scrim55,
        shape: StadiumBorder(side: BorderSide(color: AppColors.glassBorder)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
