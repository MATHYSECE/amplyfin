import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Un choix dans une liste (piste audio, sous-titres, qualité…).
class PickerOption<T> {
  const PickerOption(this.value, this.label, {this.description});

  final T value;
  final String label;

  /// Précision affichée sous le libellé (facultative).
  final String? description;
}

/// Liste de choix qui monte du bas de l'écran, avec une coche sur le choix
/// actuel. Renvoie l'option touchée, ou null si on ferme sans choisir.
Future<PickerOption<T>?> showPicker<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  required T selected,
}) {
  return showModalBottomSheet<PickerOption<T>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final option in options)
            ListTile(
              title: Text(option.label),
              subtitle: option.description == null
                  ? null
                  : Text(option.description!),
              trailing: option.value == selected
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(context).pop(option),
            ),
        ],
      ),
    ),
  );
}

/// Ligne « Audio / Français · E-AC3 5.1 › » d'une fiche, qui ouvre la liste
/// des choix quand on la touche. À placer dans un bloc en verre.
class TrackSelectorTile extends StatelessWidget {
  const TrackSelectorTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;

  /// Choix actuel, affiché sous le titre.
  final String value;

  /// Null : ligne désactivée (rien à choisir).
  final VoidCallback? onTap;

  /// Petite flèche à droite (masquée quand la place manque).
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: enabled ? AppColors.white : AppColors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (showChevron && enabled)
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.greyDark,
              ),
          ],
        ),
      ),
    );
  }
}
