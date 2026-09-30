import 'package:flutter/material.dart';

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

/// Ligne « Audio : Français · E-AC3 5.1 ▾ » d'une fiche, qui ouvre la liste
/// des choix quand on la touche.
class TrackSelectorTile extends StatelessWidget {
  const TrackSelectorTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;

  /// Choix actuel, affiché sous le titre.
  final String value;

  /// Null : ligne désactivée (rien à choisir).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
      trailing: onTap == null ? null : const Icon(Icons.expand_more),
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}
