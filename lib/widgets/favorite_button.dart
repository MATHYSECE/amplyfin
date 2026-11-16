import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/jellyfin_api.dart';
import '../models/item_details.dart';
import '../services/connection_monitor.dart';
import '../services/favorite_state.dart';
import '../theme/app_theme.dart';
import 'ui.dart';
import 'watched_controls.dart';

/// Cœur d'une fiche : ajoute le film ou la série à « Ma liste » (les
/// favoris du compte Jellyfin, les mêmes dans ses autres applis), ou l'en
/// retire. Caché tant que la fiche charge.
class FavoriteButton extends StatefulWidget {
  const FavoriteButton({
    super.key,
    required this.api,
    required this.userId,
    required this.details,
  });

  final JellyfinApi api;
  final String userId;

  /// Fiche complète (null tant qu'elle charge).
  final ItemDetails? details;

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  /// Vrai pendant l'envoi au serveur.
  bool _busy = false;

  Future<void> _toggle(String itemId, bool favorite) async {
    if (_busy) return;
    if (!ConnectionMonitor.instance.online) {
      showOfflineMessage(context);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      await FavoriteState.instance.set(
        widget.api,
        userId: widget.userId,
        itemId: itemId,
        favorite: favorite,
      );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
              favorite ? 'Ajouté à Ma liste' : 'Retiré de Ma liste',
            ),
          ),
        );
    } on JellyfinException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.details;
    if (details == null) return const SizedBox.shrink();
    final state = FavoriteState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final favorite = state.of(
          details.item.id,
          fallback: details.progress.favorite,
        );
        return GlassCircleButton(
          tooltip: favorite ? 'Retirer de Ma liste' : 'Ajouter à Ma liste',
          onPressed: () => _toggle(details.item.id, !favorite),
          // Le cœur se remplit avec un petit rebond
          child: AnimatedSwitcher(
            duration: AppDurations.medium,
            switchInCurve: Curves.easeOutBack,
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(favorite),
            ),
          ),
        );
      },
    );
  }
}
