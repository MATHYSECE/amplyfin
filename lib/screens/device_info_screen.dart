import 'package:flutter/material.dart';

import '../models/device_decoders.dart';
import '../services/device_capabilities.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Page « Ce que ton appareil sait lire » : pour chaque format vidéo, si la
/// puce le décode (définition, 10 bits), et ce qu'il en est du HDR. Ce qui
/// n'est pas lu directement est converti par le serveur avant la lecture.
class DeviceInfoScreen extends StatelessWidget {
  const DeviceInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: GlowBackground(
        child: FutureBuilder(
          future: DeviceCapabilities.decoders(),
          builder: (context, snapshot) {
            final decoders = snapshot.data;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                padding.top + 8,
                20,
                padding.bottom + 32,
              ),
              children: [
                Row(
                  children: [
                    GlassCircleButton(
                      icon: Icons.chevron_left_rounded,
                      tooltip: 'Retour',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Ce que ton appareil sait lire',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'La puce vidéo décode elle-même les formats cochés. Le reste '
                  'est converti par le serveur avant la lecture.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSoft,
                  ),
                ),
                const SizedBox(height: 20),
                if (decoders == null)
                  const Center(child: CircularProgressIndicator())
                else
                  ..._buildContent(context, decoders),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, DeviceDecoders decoders) {
    final codecs = decoders.codecs;
    final tenBit = heavyVideoCodecs.any(decoders.tenBitFor);
    return [
      const _SectionTitle('Formats vidéo'),
      if (codecs == null)
        const _InfoPanel(
          children: [
            _InfoRow(
              icon: Icons.help_outline_rounded,
              title: 'Réponse du téléphone impossible',
              detail:
                  'Tous les formats sont essayés en lecture directe, comme '
                  'avant.',
            ),
          ],
        )
      else
        _InfoPanel(
          children: [
            for (final codec in heavyVideoCodecs)
              _codecRow(codec, codecs[codec]!, decoders),
          ],
        ),
      const SizedBox(height: 20),
      const _SectionTitle('Image'),
      _InfoPanel(
        children: [
          _InfoRow(
            icon: tenBit
                ? Icons.check_circle_rounded
                : Icons.remove_circle_outline_rounded,
            title: 'HDR10 et HLG',
            detail: tenBit
                ? 'Lus directement'
                : 'Convertis par le serveur (pas de 10 bits)',
          ),
          _InfoRow(
            icon: tenBit
                ? Icons.check_circle_rounded
                : Icons.remove_circle_outline_rounded,
            title: 'Dolby Vision',
            detail: [
              if (tenBit) 'Lu comme du HDR10 (profils 7 et 8)',
              'Profil 5 converti par le serveur (couleurs justes)',
              if (decoders.dolbyVision) 'Décodeur Dolby Vision présent',
            ].join('\n'),
          ),
          _InfoRow(
            icon: decoders.hdrScreen
                ? Icons.check_circle_rounded
                : Icons.remove_circle_outline_rounded,
            title: 'Écran HDR',
            detail: decoders.hdrScreen
                ? 'Oui'
                : 'Non : les vidéos HDR sont lues quand même, parfois un '
                      'peu plus ternes',
          ),
          if (!decoders.allow10Bit)
            const _InfoRow(
              icon: Icons.info_outline_rounded,
              title: 'Émulateur',
              detail: 'Vidéos 10 bits toujours converties',
            ),
        ],
      ),
    ];
  }

  Widget _codecRow(String codec, CodecSupport support, DeviceDecoders all) {
    final name = videoCodecNames[codec] ?? codec;
    if (!support.hardware) {
      return _InfoRow(
        icon: Icons.remove_circle_outline_rounded,
        title: name,
        detail:
            'Pas de puce : lu par le processeur jusqu\'en 1080p, '
            'converti au-delà',
      );
    }
    return _InfoRow(
      icon: Icons.check_circle_rounded,
      title: name,
      detail: [
        'Puce vidéo',
        if (support.resolutionLabel != null)
          'jusqu\'en ${support.resolutionLabel}',
        all.tenBitFor(codec) ? '10 bits' : '8 bits seulement',
      ].join(' · '),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: AppColors.grey),
      ),
    );
  }
}

/// Bloc en verre qui regroupe des lignes.
class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(child: Column(children: children));
  }
}

/// Une ligne : icône (✓ ou —), nom, et détail en dessous.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final muted = icon != Icons.check_circle_rounded;
    return ListTile(
      leading: Icon(icon, color: muted ? AppColors.grey : AppColors.white),
      title: Text(title),
      subtitle: Text(detail),
    );
  }
}
