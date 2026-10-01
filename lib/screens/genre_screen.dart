import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/genre.dart';
import '../models/media_item.dart';
import '../models/session.dart';
import '../theme/app_theme.dart';
import '../widgets/genre_card.dart';
import '../widgets/media_row.dart';
import '../widgets/ui.dart';
import 'movie_screen.dart';
import 'series_screen.dart';
import 'sorted_items_screen.dart';

/// Page d'un genre : son image en grand, puis ses films et ses séries les
/// mieux notés, chacun avec « Tout voir ».
class GenreScreen extends StatelessWidget {
  const GenreScreen({
    super.key,
    required this.api,
    required this.session,
    required this.genre,
  });

  final JellyfinApi api;
  final Session session;
  final Genre genre;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: GlowBackground(
        child: ListView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 32,
          ),
          children: [
            // Image du genre, nom en grand par-dessus
            SizedBox(
              height: topInset + 220,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GenreCover(
                    api: api,
                    userId: session.userId,
                    genre: genre,
                    width: 1280,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.3, 1],
                        colors: [
                          AppColors.scrim55,
                          Colors.transparent,
                          AppColors.black,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: topInset + 8,
                    left: 16,
                    child: GlassCircleButton(
                      icon: Icons.chevron_left_rounded,
                      tooltip: 'Retour',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 12,
                    child: Text(
                      genre.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.displaySmall,
                    ),
                  ),
                ],
              ),
            ),
            if (genre.movieCount > 0)
              EntranceAnimation(
                delay: const Duration(milliseconds: 100),
                child: _GenreRow(
                  api: api,
                  session: session,
                  genre: genre,
                  type: 'Movie',
                  title: 'Films',
                ),
              ),
            if (genre.seriesCount > 0)
              EntranceAnimation(
                delay: const Duration(milliseconds: 180),
                child: _GenreRow(
                  api: api,
                  session: session,
                  genre: genre,
                  type: 'Series',
                  title: 'Séries',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rangée des films (ou séries) du genre, les mieux notés d'abord.
class _GenreRow extends StatefulWidget {
  const _GenreRow({
    required this.api,
    required this.session,
    required this.genre,
    required this.type,
    required this.title,
  });

  final JellyfinApi api;
  final Session session;
  final Genre genre;

  /// « Movie » ou « Series ».
  final String type;
  final String title;

  @override
  State<_GenreRow> createState() => _GenreRowState();
}

class _GenreRowState extends State<_GenreRow> {
  late final Future<ItemPage> _items = widget.api.getItems(
    userId: widget.session.userId,
    type: widget.type,
    limit: 20,
    sortBy: 'CommunityRating',
    genreId: widget.genre.id,
  );

  void _open(MediaItem item, String heroTag) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => item.isSeries
            ? SeriesScreen(
                api: widget.api,
                session: widget.session,
                series: item,
                heroTag: heroTag,
              )
            : MovieScreen(
                api: widget.api,
                session: widget.session,
                movie: item,
                heroTag: heroTag,
              ),
      ),
    );
  }

  void _seeAll() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SortedItemsScreen(
          api: widget.api,
          session: widget.session,
          title: '${widget.genre.name} · ${widget.title}',
          itemType: widget.type,
          sortBy: 'CommunityRating',
          genreId: widget.genre.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: FutureBuilder(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const SizedBox.shrink();
          final page = snapshot.data;
          if (page == null) return const MediaRowSkeleton();
          if (page.items.isEmpty) return const SizedBox.shrink();
          return MediaRow(
            title: widget.title,
            onSeeAll: _seeAll,
            children: [
              for (final item in page.items)
                MediaTile(
                  api: widget.api,
                  item: item,
                  title: item.name,
                  subtitle: item.year?.toString() ?? '',
                  heroTag: 'genre-${item.id}',
                  onTap: () => _open(item, 'genre-${item.id}'),
                ),
            ],
          );
        },
      ),
    );
  }
}
