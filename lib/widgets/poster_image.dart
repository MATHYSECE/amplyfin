import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/media_item.dart';

/// Affiche d'un film ou d'une série aux coins arrondis (via le thème, Card).
/// Utilisée dans la grille et sur la fiche : même adresse partout, donc
/// l'image déjà chargée dans la grille s'affiche tout de suite sur la fiche.
class PosterImage extends StatelessWidget {
  const PosterImage({super.key, required this.api, required this.item});

  /// Largeur demandée au serveur, en pixels : assez nette pour une affiche
  /// de grille ou de fiche, sans être trop lourde.
  static const pixelWidth = 400;

  final JellyfinApi api;
  final MediaItem item;

  /// Nom commun de l'animation « l'affiche glisse de la grille vers la fiche ».
  static String heroTag(MediaItem item) => 'poster-${item.id}';

  /// Même chose depuis l'écran des téléchargements (nom à part : sinon
  /// l'affiche de la bibliothèque volerait aussi vers cet écran).
  static String downloadHeroTag(MediaItem item) => 'download-poster-${item.id}';

  @override
  Widget build(BuildContext context) {
    final url = api.posterUrl(item, width: pixelWidth);
    return Card(
      child: url == null
          ? const PosterPlaceholder()
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              // Image décodée à la taille demandée : économise la mémoire
              memCacheWidth: pixelWidth,
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, _) => const SizedBox.shrink(),
              errorWidget: (_, _, _) => const PosterPlaceholder(),
            ),
    );
  }
}

/// Affichée quand un film n'a pas d'affiche (ou si elle ne charge pas).
class PosterPlaceholder extends StatelessWidget {
  const PosterPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.movie_outlined,
        size: 40,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
