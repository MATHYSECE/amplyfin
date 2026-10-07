import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/next_episode.dart';
import '../services/device_capabilities.dart';
import '../theme/app_theme.dart';

/// Carte « Épisode suivant » en bas à droite du lecteur, pendant le
/// générique : vignette, titre, compte à rebours (anneau qui se remplit,
/// arrêté quand la vidéo est en pause) puis lecture automatique.
class NextEpisodeCard extends StatefulWidget {
  const NextEpisodeCard({
    super.key,
    required this.episode,
    required this.running,
    required this.onPlayNow,
    required this.onTimeout,
    required this.onDismiss,
    this.playFocusNode,
  });

  final NextEpisode episode;

  /// Télé : « Lire maintenant », sélectionné par le lecteur quand la carte
  /// apparaît.
  final FocusNode? playFocusNode;

  /// Vrai quand la vidéo avance : le compte à rebours aussi.
  final ValueListenable<bool> running;

  /// « Lire maintenant ».
  final VoidCallback onPlayNow;

  /// Fin du compte à rebours (lecture automatique).
  final VoidCallback onTimeout;

  /// « Regarder le générique » : la carte disparaît.
  final VoidCallback onDismiss;

  @override
  State<NextEpisodeCard> createState() => _NextEpisodeCardState();
}

class _NextEpisodeCardState extends State<NextEpisodeCard>
    with SingleTickerProviderStateMixin {
  late final _countdown = AnimationController(
    vsync: this,
    duration: nextEpisodeCountdown,
  );

  @override
  void initState() {
    super.initState();
    _countdown.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onTimeout();
    });
    widget.running.addListener(_onRunningChanged);
    _onRunningChanged();
  }

  @override
  void dispose() {
    widget.running.removeListener(_onRunningChanged);
    _countdown.dispose();
    super.dispose();
  }

  void _onRunningChanged() {
    if (widget.running.value) {
      _countdown.forward();
    } else {
      _countdown.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final episode = widget.episode;
    // Fond sombre sans flou : le flou ne s'affiche pas par-dessus la vidéo
    // sur Android (la vidéo est dessinée à part par la puce)
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.scrim85,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.poster),
                  child: SizedBox(
                    width: 128,
                    height: 72,
                    child: _Thumbnail(episode: episode),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ÉPISODE SUIVANT',
                        style: textTheme.labelSmall?.copyWith(
                          color: AppColors.grey,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        episode.subtitle ?? episode.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    // Télé : sélectionné dès que la carte apparaît
                    autofocus: DeviceCapabilities.isTv,
                    focusNode: widget.playFocusNode,
                    onPressed: widget.onPlayNow,
                    child: AnimatedBuilder(
                      animation: _countdown,
                      builder: (context, _) {
                        final left =
                            (nextEpisodeCountdown.inSeconds *
                                    (1 - _countdown.value))
                                .ceil();
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CountdownRing(value: _countdown.value),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Lecture dans $left s',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: widget.onDismiss,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSoft,
                  ),
                  child: const Text('Regarder le générique'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Anneau du compte à rebours, avec le symbole lecture au milieu.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color ?? AppColors.black;
    return SizedBox.square(
      dimension: 22,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: value,
            strokeWidth: 2,
            color: color,
            backgroundColor: color.withValues(alpha: 0.2),
          ),
          Icon(Icons.play_arrow_rounded, size: 16, color: color),
        ],
      ),
    );
  }
}

/// Vignette de l'épisode : fichier du téléphone, image du serveur, ou fond
/// uni s'il n'y en a pas.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.episode});

  final NextEpisode episode;

  @override
  Widget build(BuildContext context) {
    const empty = ColoredBox(color: AppColors.surface3);
    final path = episode.imagePath;
    if (path != null) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => empty,
      );
    }
    final url = episode.imageUrl;
    if (url == null) return empty;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 256,
      placeholder: (_, _) => empty,
      errorWidget: (_, _, _) => empty,
    );
  }
}

/// « Tu regardes toujours ? » par-dessus la vidéo (après plusieurs épisodes
/// enchaînés sans toucher l'écran).
class StillWatchingOverlay extends StatelessWidget {
  const StillWatchingOverlay({
    super.key,
    required this.episode,
    required this.onContinue,
    required this.onStop,
    this.continueFocusNode,
  });

  /// Épisode qui sera lu en continuant.
  final NextEpisode episode;

  /// Télé : « Continuer », sélectionné par le lecteur.
  final FocusNode? continueFocusNode;
  final VoidCallback onContinue;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ColoredBox(
      color: AppColors.scrim85,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tu regardes toujours ?',
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                [episode.title, ?episode.subtitle].join(' · '),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(color: AppColors.grey),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: onStop,
                    child: const Text('Arrêter'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    autofocus: DeviceCapabilities.isTv,
                    focusNode: continueFocusNode,
                    onPressed: onContinue,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Continuer'),
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
