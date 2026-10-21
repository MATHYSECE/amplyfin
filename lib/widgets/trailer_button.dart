import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/session.dart';
import '../models/trailer.dart';
import '../services/playback_launcher.dart';
import 'track_picker.dart';

/// Bouton « Bande-annonce » d'une fiche (film ou série). Il demande au
/// serveur les bandes-annonces rangées à côté de la vidéo, et ne s'affiche
/// que s'il y en a (rien hors ligne). Une seule : lue tout de suite ;
/// plusieurs : liste pour choisir. Lue dans notre lecteur, sans rien
/// enregistrer (ni reprise, ni « Continuer à regarder »).
class TrailerButton extends StatefulWidget {
  const TrailerButton({
    super.key,
    required this.api,
    required this.session,
    required this.itemId,
    required this.title,
    this.padding = EdgeInsets.zero,
  });

  final JellyfinApi api;
  final Session session;

  /// Film ou série dont on cherche les bandes-annonces.
  final String itemId;

  /// Titre affiché en haut du lecteur.
  final String title;

  /// Marge autour du bouton (seulement s'il s'affiche).
  final EdgeInsets padding;

  @override
  State<TrailerButton> createState() => _TrailerButtonState();
}

class _TrailerButtonState extends State<TrailerButton> {
  List<Trailer> _trailers = const [];
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final trailers = await widget.api.getLocalTrailers(
        userId: widget.session.userId,
        itemId: widget.itemId,
      );
      if (mounted) setState(() => _trailers = trailers);
    } on Exception {
      // Serveur injoignable : pas de bouton
    }
  }

  Future<void> _onPressed() async {
    var trailer = _trailers.first;
    if (_trailers.length > 1) {
      final chosen = await showPicker<Trailer?>(
        context,
        title: 'Bandes-annonces',
        options: [
          for (final (i, t) in _trailers.indexed)
            PickerOption(t, t.label(i + 1, _trailers.length)),
        ],
        selected: null,
      );
      final value = chosen?.value;
      if (value == null || !mounted) return;
      trailer = value;
    }
    setState(() => _starting = true);
    await launchPlayback(
      context,
      api: widget.api,
      session: widget.session,
      itemId: trailer.id,
      title: widget.title,
      subtitle: 'Bande-annonce',
      trailer: true,
    );
    if (mounted) setState(() => _starting = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_trailers.isEmpty) return const SizedBox.shrink();
    final count = _trailers.length;
    return Padding(
      padding: widget.padding,
      child: OutlinedButton.icon(
        onPressed: _starting ? null : _onPressed,
        icon: const Icon(Icons.movie_outlined, size: 22),
        label: Text(count > 1 ? 'Bandes-annonces ($count)' : 'Bande-annonce'),
      ),
    );
  }
}
