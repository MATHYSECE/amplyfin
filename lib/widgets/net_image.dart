import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

import '../theme/app_theme.dart';

/// Image du serveur qui s'affiche tout de suite en flou ([blurHash] : ses
/// couleurs, envoyées par le serveur avec la fiche), puis devient nette en
/// fondu dès qu'elle est arrivée. Sans aperçu : [placeholder] (vide par
/// défaut) pendant le chargement.
class NetImage extends StatelessWidget {
  const NetImage({
    super.key,
    required this.url,
    this.blurHash,
    this.memCacheWidth,
    this.fit = BoxFit.cover,
    this.fadeIn = AppDurations.medium,
    this.placeholder,
    this.error,
  });

  final String url;
  final String? blurHash;

  /// Largeur à laquelle l'image est décodée (économise la mémoire).
  final int? memCacheWidth;
  final BoxFit fit;
  final Duration fadeIn;

  /// Pendant le chargement, quand il n'y a pas d'aperçu.
  final Widget? placeholder;

  /// Si l'image ne charge pas (hors ligne…) : l'aperçu flou sinon.
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    final hash = blurHash;
    final waiting = hash != null
        ? BlurHashBox(hash)
        : (placeholder ?? const SizedBox.shrink());
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: memCacheWidth,
      fadeInDuration: fadeIn,
      fadeOutDuration: AppDurations.medium,
      placeholder: (_, _) => waiting,
      errorWidget: (_, _, _) => error ?? waiting,
    );
  }
}

/// Aperçu flou d'une image (décodé en 32 × 32 puis étiré : très léger,
/// gardé en mémoire comme une image).
class BlurHashBox extends StatelessWidget {
  const BlurHashBox(this.hash, {super.key});

  final String hash;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: BlurHashImage(hash),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      // Aperçu illisible : rien (la vraie image arrive quand même)
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}
