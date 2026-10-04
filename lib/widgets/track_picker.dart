import 'package:flutter/material.dart';

import '../models/media_track.dart';
import '../models/player_codecs.dart';
import '../services/device_capabilities.dart';
import '../theme/app_theme.dart';
import 'tv_focus.dart';

/// Un choix dans une liste (piste audio, sous-titres, qualité…).
class PickerOption<T> {
  const PickerOption(
    this.value,
    this.label, {
    this.description,
    this.enabled = true,
  });

  final T value;
  final String label;

  /// Précision affichée sous le libellé (facultative).
  final String? description;

  /// Faux pour un choix grisé, qu'on ne peut pas toucher.
  final bool enabled;
}

/// Choix d'une piste audio. Son que le lecteur ne lit pas : converti par
/// le serveur, ou grisé pour un fichier téléchargé ([local], rien à
/// convertir sans le serveur).
PickerOption<int?> audioTrackOption(
  MediaTrack track,
  PlayerCodecs player, {
  bool local = false,
}) {
  final playable = player.playsAudio(track);
  return PickerOption(
    track.index,
    track.label,
    enabled: playable || !local,
    description: playable
        ? null
        : local
        ? 'Illisible sur cet appareil'
        : 'Son converti par le serveur',
  );
}

/// Choix de sous-titres : grisés si le lecteur ne sait pas les afficher
/// (sous-titres en images PGS).
PickerOption<int> subtitleTrackOption(MediaTrack track, PlayerCodecs player) {
  final available = player.showsSubtitle(track);
  return PickerOption(
    track.index,
    track.label,
    enabled: available,
    description: available ? null : 'Non disponible sur cet appareil',
  );
}

/// Ligne de réglage sous les choix d'une liste (ex. « Taille des
/// sous-titres · Moyenne »), qui ferme la liste puis lance [onTap].
class PickerExtra {
  const PickerExtra({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;

  /// Réglage actuel, affiché sous le libellé.
  final String value;
  final VoidCallback onTap;
}

/// Liste de choix qui monte du bas de l'écran, avec une coche sur le choix
/// actuel. Renvoie l'option touchée, ou null si on ferme sans choisir.
/// [extra] : ligne de réglage facultative, sous les choix.
Future<PickerOption<T>?> showPicker<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  required T selected,
  PickerExtra? extra,
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
              enabled: option.enabled,
              title: Text(option.label),
              subtitle: option.description == null
                  ? null
                  : Text(option.description!),
              trailing: option.value == selected
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(context).pop(option),
            ),
          if (extra != null) ...[
            const Divider(),
            ListTile(
              leading: Icon(extra.icon),
              title: Text(extra.label),
              subtitle: Text(extra.value),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.greyDark,
              ),
              onTap: () {
                Navigator.of(context).pop();
                extra.onTap();
              },
            ),
          ],
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
    // Télé : ligne sélectionnable avec le contour blanc commun
    return TvFocusable(
      onTap: onTap,
      radius: AppRadius.card,
      scale: 1.02,
      child: _buildRow(textTheme, enabled),
    );
  }

  Widget _buildRow(TextTheme textTheme, bool enabled) {
    return InkWell(
      onTap: onTap,
      canRequestFocus: !DeviceCapabilities.isTv,
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
