import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/item_details.dart';
import '../models/media_item.dart';
import '../models/search_results.dart';
import '../models/session.dart';
import '../screens/movie_screen.dart';
import '../screens/series_screen.dart';
import '../screens/sorted_items_screen.dart';
import '../services/connection_monitor.dart';
import 'media_row.dart';
import 'people_row.dart';
import 'ui.dart';
import 'watched_controls.dart';

/// Bas d'une fiche : la distribution (acteurs, réalisation), puis les
/// titres similaires proposés par le serveur. Chaque rangée n'apparaît que
/// si elle a quelque chose à montrer (rien hors ligne).
class DetailsExtras extends StatefulWidget {
  const DetailsExtras({
    super.key,
    required this.api,
    required this.session,
    required this.item,
    required this.details,
  });

  final JellyfinApi api;
  final Session session;
  final MediaItem item;

  /// Fiche complète (null tant qu'elle charge) : elle donne la distribution.
  final ItemDetails? details;

  @override
  State<DetailsExtras> createState() => _DetailsExtrasState();
}

class _DetailsExtrasState extends State<DetailsExtras> {
  List<MediaItem> _similar = const [];

  @override
  void initState() {
    super.initState();
    _loadSimilar();
  }

  Future<void> _loadSimilar() async {
    if (!ConnectionMonitor.instance.online) return;
    try {
      final similar = await widget.api.getSimilar(
        userId: widget.session.userId,
        itemId: widget.item.id,
      );
      if (mounted) setState(() => _similar = similar);
    } on Exception {
      // Pas grave : la rangée ne s'affiche pas
    }
  }

  /// Films et séries d'une personne, du plus récent au plus ancien.
  void _openPerson(SearchPerson person) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SortedItemsScreen(
          api: widget.api,
          session: widget.session,
          title: person.name,
          itemType: 'Movie,Series',
          sortBy: 'ProductionYear',
          personId: person.id,
        ),
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final people = widget.details?.people ?? const <SearchPerson>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (people.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 30),
            child: EntranceAnimation(
              child: PeopleRow(
                api: widget.api,
                title: 'Distribution',
                people: people,
                onOpen: _openPerson,
              ),
            ),
          ),
        if (_similar.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 30),
            child: EntranceAnimation(
              child: MediaRow(
                title: 'Titres similaires',
                children: [
                  for (final item in _similar)
                    MediaTile(
                      api: widget.api,
                      item: item,
                      title: item.name,
                      subtitle: item.year?.toString() ?? '',
                      // Nom propre à cette fiche : le même film peut être
                      // proposé sur la fiche d'en dessous
                      heroTag: 'similar-${widget.item.id}-${item.id}',
                      overlays: [
                        Positioned(
                          top: 6,
                          left: 6,
                          child: WatchedBadge(item: item),
                        ),
                      ],
                      onTap: () =>
                          _open(item, 'similar-${widget.item.id}-${item.id}'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
