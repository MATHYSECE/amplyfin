import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/genre.dart';
import '../models/item_details.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Image de chaque genre (un film ou une série récente du genre), choisie
/// une seule fois pendant que l'appli est ouverte.
final Map<String, Future<ItemDetails?>> _covers = {};

/// Choisit d'un coup les images des [genres] affichés ensemble, sans
/// reprendre le même titre sur deux genres.
void prepareGenreCovers(JellyfinApi api, String userId, List<Genre> genres) {
  final missing = [
    for (final genre in genres)
      if (!_covers.containsKey(genre.id)) genre,
  ];
  if (missing.isEmpty) return;
  final failed = <String>{};
  Future<List<ItemDetails>> candidates(Genre genre) async {
    try {
      return await api.getGenreCovers(userId: userId, genreId: genre.id);
    } on JellyfinException {
      failed.add(genre.id);
      return [];
    }
  }

  final picked = Future(() async {
    final lists = await Future.wait(missing.map(candidates));
    // Genres sans réponse : redemandés la prochaine fois
    for (final id in failed) {
      _covers.remove(id);
    }
    return pickDistinctCovers({
      for (final (i, genre) in missing.indexed) genre.id: lists[i],
    }, (cover) => cover.item.id);
  });
  for (final genre in missing) {
    _covers[genre.id] = picked.then((covers) => covers[genre.id]);
  }
}

/// Image du genre [genre] (null s'il n'y en a pas, ou si le serveur ne
/// répond pas).
Future<ItemDetails?> genreCover(JellyfinApi api, String userId, Genre genre) {
  prepareGenreCovers(api, userId, [genre]);
  return _covers[genre.id]!;
}

/// Image de fond d'un genre, assombrie en bas (pour lire le nom dessus).
class GenreCover extends StatelessWidget {
  const GenreCover({
    super.key,
    required this.api,
    required this.userId,
    required this.genre,
    this.width = 640,
  });

  final JellyfinApi api;
  final String userId;
  final Genre genre;

  /// Largeur demandée au serveur, en pixels.
  final int width;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.surface3),
        FutureBuilder(
          future: genreCover(api, userId, genre),
          builder: (context, snapshot) {
            final cover = snapshot.data;
            final url = cover == null
                ? null
                : api.backdropUrl(cover, width: width);
            if (url == null) return const SizedBox.shrink();
            return CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              memCacheWidth: width,
              fadeInDuration: AppDurations.medium,
              placeholder: (_, _) => const SizedBox.shrink(),
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            );
          },
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.2, 1],
              colors: [Colors.transparent, AppColors.scrim70],
            ),
          ),
        ),
      ],
    );
  }
}

/// Carte d'un genre (« Parcourir par genre ») : image et nom, s'enfonce un
/// peu à l'appui.
class GenreCard extends StatelessWidget {
  const GenreCard({
    super.key,
    required this.api,
    required this.userId,
    required this.genre,
    required this.onTap,
  });

  final JellyfinApi api;
  final String userId;
  final Genre genre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GenreCover(api: api, userId: userId, genre: genre, width: 480),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Text(
                  genre.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    shadows: const [
                      Shadow(color: AppColors.scrim70, blurRadius: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
