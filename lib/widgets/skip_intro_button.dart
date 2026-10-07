import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'tv_focus.dart';

/// Bouton « Passer l'intro » (en bas à droite du lecteur, pendant le
/// générique de début). Pilule blanche, comme les boutons principaux.
/// Télé : [focusNode] permet au lecteur de le sélectionner dès qu'il
/// apparaît (OK suffit alors pour sauter).
class SkipIntroButton extends StatelessWidget {
  const SkipIntroButton({super.key, required this.onPressed, this.focusNode});

  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: onPressed,
      focusNode: focusNode,
      radius: AppRadius.pill,
      scale: 1.08,
      child: ExcludeFocus(
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            // Blanc plein partout (la télé ne le grise pas)
            backgroundColor: AppColors.white,
            foregroundColor: AppColors.black,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 22),
          ),
          icon: const Icon(Icons.skip_next_rounded, size: 24),
          label: const Text('Passer l\'intro'),
        ),
      ),
    );
  }
}
