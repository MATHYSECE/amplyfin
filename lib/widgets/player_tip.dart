import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tour.dart';
import '../theme/app_theme.dart';

/// Astuce de la toute première lecture (une fois par profil) : rappel des
/// gestes (téléphone), de la télécommande (télé) ou du clavier (PC), sur
/// un voile sombre. Pas de flou : il ne s'afficherait pas par-dessus la
/// vidéo sur Android. Elle ne bloque rien (le geste ou la touche agit
/// aussi sur le lecteur) et disparaît à la première touche, avec
/// « Compris », ou seule après [_autoHide]. Le lecteur la ferme aussi au
/// premier appui sur l'écran.
class PlayerTip extends StatefulWidget {
  const PlayerTip({super.key, required this.device, required this.onDismiss});

  final TourDevice device;
  final VoidCallback onDismiss;

  @override
  State<PlayerTip> createState() => _PlayerTipState();
}

class _PlayerTipState extends State<PlayerTip> {
  static const _autoHide = Duration(seconds: 15);

  Timer? _timer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_autoHide, _dismiss);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Une touche (télécommande, clavier) : l'astuce disparaît, et la
  /// touche agit quand même sur le lecteur.
  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) _dismiss();
    return false;
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: ColoredBox(
            color: AppColors.scrim70,
            child: switch (widget.device) {
              TourDevice.touch => const _Gestures(),
              TourDevice.tv => const _Keys(keys: tvPlayerKeys),
              TourDevice.desktop => const _Keys(keys: desktopPlayerKeys),
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.device == TourDevice.touch
                      ? 'Un appui affiche les commandes'
                      : 'Les commandes apparaissent à la première touche',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _dismiss, child: const Text('Compris')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Téléphone : à gauche luminosité et recul, à droite volume et avance.
class _Gestures extends StatelessWidget {
  const _Gestures();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (slide, tap) in const [
          ('Luminosité', '−10'),
          ('Volume', '+10'),
        ])
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Hint(
                      label: slide,
                      child: const Icon(Icons.swipe_vertical_rounded),
                    ),
                    const SizedBox(width: 18),
                    _Hint(label: 'Double appui', child: Text(tap)),
                  ],
                ),
                const SizedBox(height: 70),
              ],
            ),
          ),
      ],
    );
  }
}

/// Un rond (icône ou texte) et sa légende.
class _Hint extends StatelessWidget {
  const _Hint({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.outlineStrong),
          ),
          child: DefaultTextStyle.merge(
            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            child: child,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

/// Télé ou PC : les touches du lecteur et leur effet.
class _Keys extends StatelessWidget {
  const _Keys({required this.keys});

  final List<TourKey> keys;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 90),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in keys)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 170,
                        child: Text(
                          entry.key,
                          textAlign: TextAlign.right,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Text(
                          entry.action,
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
