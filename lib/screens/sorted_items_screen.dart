import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/media_item.dart';
import '../models/session.dart';
import '../theme/app_theme.dart';
import '../widgets/library_grid.dart';
import '../widgets/ui.dart';
import 'movie_screen.dart';
import 'series_screen.dart';

/// « Tout voir » d'une rangée de l'accueil : la grille complète, du plus
/// récent au plus ancien (ajoutés, ou sortis récemment). Sert aussi pour
/// les films et séries d'un acteur ([personId]) ou d'un genre ([genreId]).
class SortedItemsScreen extends StatelessWidget {
  const SortedItemsScreen({
    super.key,
    required this.api,
    required this.session,
    required this.title,
    required this.itemType,
    required this.sortBy,
    this.releasedBefore,
    this.personId,
    this.genreId,
  });

  final JellyfinApi api;
  final Session session;
  final String title;

  /// « Movie » ou « Series ».
  final String itemType;

  /// Tri pour le serveur : « DateCreated » ou « PremiereDate ».
  final String sortBy;
  final DateTime? releasedBefore;
  final String? personId;
  final String? genreId;

  void _open(BuildContext context, MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => item.isSeries
            ? SeriesScreen(api: api, session: session, series: item)
            : MovieScreen(api: api, session: session, movie: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final headerHeight = topInset + 64;
    return Scaffold(
      body: GlowBackground(
        child: Stack(
          children: [
            LibraryGrid(
              api: api,
              session: session,
              itemType: itemType,
              sortBy: sortBy,
              releasedBefore: releasedBefore,
              personId: personId,
              genreId: genreId,
              emptyMessage: 'Rien à afficher pour l\'instant.',
              topPadding: headerHeight,
              onOpen: (item) => _open(context, item),
              onUnauthorized: () => Navigator.of(context).maybePop(),
            ),
            // En-tête en verre dépoli : retour et titre
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    height: headerHeight,
                    color: AppColors.scrim55,
                    padding: EdgeInsets.fromLTRB(16, topInset + 8, 20, 10),
                    child: Row(
                      children: [
                        GlassCircleButton(
                          icon: Icons.chevron_left_rounded,
                          tooltip: 'Retour',
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
