import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/item_details.dart';
import '../models/media_item.dart';
import '../models/session.dart';
import '../widgets/details_page.dart';
import 'player_screen.dart';

/// Fiche d'un film : image de fond, affiche, infos, bouton lecture, résumé.
/// Le titre, l'année et l'affiche (déjà connus grâce à la grille) s'affichent
/// tout de suite ; le reste arrive quand le serveur a répondu.
class MovieScreen extends StatefulWidget {
  const MovieScreen({
    super.key,
    required this.api,
    required this.session,
    required this.movie,
  });

  final JellyfinApi api;
  final Session session;
  final MediaItem movie;

  @override
  State<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> {
  ItemDetails? _details;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Demande la fiche complète au serveur.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = await widget.api.getItemDetails(
        userId: widget.session.userId,
        itemId: widget.movie.id,
      );
      if (mounted) setState(() => _details = details);
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _play() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          api: widget.api,
          session: widget.session,
          itemId: widget.movie.id,
          title: widget.movie.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final details = _details;

    return DetailsPage(
      api: widget.api,
      item: movie,
      details: details,
      showBackdropFallback: !_loading,
      children: [
        DetailsHeader(
          api: widget.api,
          item: movie,
          infos: [
            if (movie.year != null) '${movie.year}',
            ?details?.runtimeLabel,
            ?details?.officialRating,
          ],
          rating: details?.ratingLabel,
          // Qualité du fichier : 4K, HEVC, HDR10, E-AC3 5.1…
          chips: details?.quality?.labels ?? const [],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _play,
          icon: const Icon(Icons.play_arrow),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Lecture'),
          ),
        ),
        const SizedBox(height: 24),
        if (details != null)
          DetailsOverview(details: details)
        else if (_error != null)
          RetryMessage(message: _error!, onRetry: _load)
        else
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
