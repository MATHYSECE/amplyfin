import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/media_item.dart';
import '../models/watch_progress.dart';
import '../services/connection_monitor.dart';
import '../services/watched_state.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Marque « vu » sur une affiche (en haut à gauche, la coche « téléchargé »
/// étant à droite) : coche sur un film vu ou une série toute vue, nombre
/// d'épisodes pas vus sur une série commencée ou pas.
class WatchedBadge extends StatelessWidget {
  const WatchedBadge({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final state = WatchedState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final progress = state.of(item);
        final unplayed = progress.unplayedCount;
        final Widget? child;
        if (progress.played) {
          child = const Icon(
            Icons.check_rounded,
            size: 14,
            color: AppColors.white,
          );
        } else if (item.isSeries && unplayed != null && unplayed > 0) {
          child = Text(
            '$unplayed',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppColors.white, fontWeight: FontWeight.w800),
          );
        } else {
          child = null;
        }
        return AnimatedScale(
          scale: child == null ? 0 : 1,
          duration: AppDurations.medium,
          curve: Curves.easeOutBack,
          child: Container(
            constraints: const BoxConstraints(minWidth: 22),
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: const ShapeDecoration(
              color: AppColors.scrim70,
              shape: StadiumBorder(
                side: BorderSide(color: AppColors.outlineStrong),
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

/// Bouton rond « Vu » d'une fiche : blanc avec une coche noire quand c'est
/// vu, en verre sinon. Grisé hors ligne.
class WatchedButton extends StatelessWidget {
  const WatchedButton({
    super.key,
    required this.played,
    required this.onPressed,
    this.size = 52,
    this.seriesWide = false,
  });

  final bool played;

  /// Null pendant un changement en cours.
  final VoidCallback? onPressed;
  final double size;

  /// Vrai pour une série ou une saison entière (texte de l'aide).
  final bool seriesWide;

  @override
  Widget build(BuildContext context) {
    final what = seriesWide ? 'tout ' : '';
    return ListenableBuilder(
      listenable: ConnectionMonitor.instance,
      builder: (context, _) {
        final online = ConnectionMonitor.instance.online;
        return Tooltip(
          message: !online
              ? 'Disponible avec une connexion'
              : played
              ? 'Marquer ${what}comme pas vu'
              : 'Marquer ${what}comme vu',
          child: AnimatedOpacity(
            opacity: online ? 1 : 0.4,
            duration: AppDurations.fast,
            child: Material(
              color: played ? AppColors.white : AppColors.scrim35,
              shape: CircleBorder(
                side: BorderSide(
                  color: played ? AppColors.white : AppColors.glassBorder,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: online ? onPressed : () => showOfflineMessage(context),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Icon(
                    Icons.check_rounded,
                    size: size * 0.46,
                    color: played ? AppColors.black : AppColors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Message « Disponible avec une connexion ».
void showOfflineMessage(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Disponible avec une connexion.')),
  );
}

/// Marque un film ou un épisode comme vu / pas vu, avec « Annuler » quelques
/// secondes (qui remet aussi la position de reprise). [related] : éléments
/// dont l'état change aussi (la série d'un épisode). [onChanged] : appelé
/// après chaque changement (pour recharger l'écran). Renvoie faux en cas
/// d'échec (message déjà affiché).
Future<bool> toggleWatched(
  BuildContext context, {
  required JellyfinApi api,
  required String userId,
  required String itemId,
  required WatchProgress current,
  List<String> related = const [],
  VoidCallback? onChanged,
}) async {
  if (!ConnectionMonitor.instance.online) {
    showOfflineMessage(context);
    return false;
  }
  final messenger = ScaffoldMessenger.of(context);
  final played = !current.played;
  final state = WatchedState.instance;
  try {
    await state.setPlayed(
      api,
      userId: userId,
      itemId: itemId,
      played: played,
      related: related,
    );
  } on JellyfinException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
  onChanged?.call();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(played ? 'Marqué comme vu' : 'Marqué comme pas vu'),
        // Disparaît tout seul, même avec un bouton
        persist: false,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Annuler',
          textColor: AppColors.white,
          onPressed: () async {
            try {
              await state.restore(
                api,
                userId: userId,
                itemId: itemId,
                previous: current,
                related: related,
              );
            } on JellyfinException catch (e) {
              messenger.showSnackBar(SnackBar(content: Text(e.message)));
              return;
            }
            onChanged?.call();
          },
        ),
      ),
    );
  return true;
}

/// Marque toute une saison ou toute une série comme vue / pas vue, après
/// confirmation ([what] : « la saison 2 », « toute la série »). Pas
/// d'« Annuler » : l'état de chaque épisode serait perdu.
Future<bool> setWatchedForAll(
  BuildContext context, {
  required JellyfinApi api,
  required String userId,
  required String itemId,
  required String what,
  required bool played,
  List<String> related = const [],
}) async {
  if (!ConnectionMonitor.instance.online) {
    showOfflineMessage(context);
    return false;
  }
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showConfirmDialog(
    context,
    title: played ? 'Marquer $what comme vu ?' : 'Marquer $what comme pas vu ?',
    message: played
        ? 'Tous les épisodes seront cochés comme vus.'
        : 'Tous les épisodes seront remis comme jamais vus, positions de '
              'reprise comprises.',
    action: played ? 'Marquer comme vu' : 'Marquer comme pas vu',
    cancel: 'Annuler',
  );
  if (!confirmed) return false;
  try {
    await WatchedState.instance.setPlayed(
      api,
      userId: userId,
      itemId: itemId,
      played: played,
      related: related,
    );
  } on JellyfinException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          played ? 'Tout est marqué comme vu' : 'Tout est marqué comme pas vu',
        ),
      ),
    );
  return true;
}
