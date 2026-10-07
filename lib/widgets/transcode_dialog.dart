import 'package:flutter/material.dart';

import '../models/transcode_reasons.dart';
import '../services/device_capabilities.dart';
import '../theme/app_theme.dart';
import 'error_details.dart';

/// Fenêtre « Lecture directe impossible » : explique pourquoi, liste ce que
/// la conversion change, et demande à l'utilisateur s'il veut convertir.
/// [detail] : message technique du lecteur, montré à la demande.
/// Renvoie true pour « Convertir et lire », false sinon.
Future<bool> showTranscodeDialog(
  BuildContext context, {
  required List<String> reasonCodes,
  String? detail,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim70,
    builder: (context) =>
        _TranscodeDialog(reasonCodes: reasonCodes, detail: detail),
  );
  return accepted ?? false;
}

class _TranscodeDialog extends StatelessWidget {
  const _TranscodeDialog({required this.reasonCodes, this.detail});

  final List<String> reasonCodes;
  final String? detail;

  /// Ce que la conversion change pour l'utilisateur.
  static const _consequences = [
    'Image un peu moins nette',
    'Démarrage plus long (10 à 30 secondes)',
    'Avance et retour rapides plus lents',
    'Serveur plus sollicité (risque de saccades)',
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final reasons = describeTranscodeReasons(
      reasonCodes.isEmpty ? const ['DirectPlayError'] : reasonCodes,
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: DecoratedBox(
          // Léger halo blanc en haut de la fenêtre
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -1.3),
              radius: 1.2,
              colors: [AppColors.glassStrong, Colors.transparent],
            ),
          ),
          // Défile si l'écran est petit (téléphone à l'horizontale)
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: const ShapeDecoration(
                      color: AppColors.glassStrong,
                      shape: CircleBorder(
                        side: BorderSide(color: AppColors.glassBorder),
                      ),
                    ),
                    child: const Icon(Icons.warning_amber_rounded, size: 26),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Lecture directe impossible', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final reason in reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      reason,
                      style: textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSoft,
                      ),
                    ),
                  ),
                Text(
                  'Le serveur peut convertir le fichier pendant la lecture.',
                  style: textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSoft,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Ce que ça change',
                  style: textTheme.labelLarge?.copyWith(color: AppColors.grey),
                ),
                const SizedBox(height: 10),
                for (final consequence in _consequences)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(consequence, style: textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                FilledButton(
                  autofocus: DeviceCapabilities.isTv,
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Convertir et lire'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                if (detail != null) ErrorDetails(detail!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
