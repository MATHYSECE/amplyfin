import 'package:flutter/foundation.dart';

import '../api/jellyfin_api.dart';
import '../models/media_item.dart';
import '../models/watch_progress.dart';

/// « Vu / pas vu » marqué depuis l'appli : retient le nouvel état de chaque
/// élément changé, pour que les affiches déjà chargées (grilles) se mettent
/// à jour sans tout recharger.
class WatchedState extends ChangeNotifier {
  WatchedState._();

  static final instance = WatchedState._();

  /// État après un changement, par identifiant (film, épisode, série).
  final _changed = <String, WatchProgress>{};

  /// État d'un élément : le dernier changement, sinon ce qu'a dit le serveur
  /// au chargement.
  WatchProgress of(MediaItem item) => _changed[item.id] ?? item.progress;

  /// Changement de profil : les « vu / pas vu » retenus étaient ceux de
  /// l'autre personne.
  void reset() {
    _changed.clear();
    notifyListeners();
  }

  /// Marque [itemId] comme vu ou pas vu sur le serveur, puis relit son état
  /// et celui des éléments [related] (ex. la série d'un épisode : son nombre
  /// d'épisodes pas vus change aussi).
  Future<void> setPlayed(
    JellyfinApi api, {
    required String userId,
    required String itemId,
    required bool played,
    List<String> related = const [],
  }) async {
    await api.setPlayed(userId: userId, itemId: itemId, played: played);
    await refresh(api, userId: userId, itemIds: [itemId, ...related]);
  }

  /// Remet un film ou un épisode comme avant (« Annuler ») : pas vu, à la
  /// même position de reprise.
  Future<void> restore(
    JellyfinApi api, {
    required String userId,
    required String itemId,
    required WatchProgress previous,
    List<String> related = const [],
  }) async {
    await api.updateWatchProgress(
      userId: userId,
      itemId: itemId,
      position: previous.position,
      played: previous.played,
      lastPlayed: previous.lastPlayed,
    );
    await refresh(api, userId: userId, itemIds: [itemId, ...related]);
  }

  /// Relit l'état de ces éléments sur le serveur (une erreur est ignorée :
  /// le changement est fait, seules les marques attendront).
  Future<void> refresh(
    JellyfinApi api, {
    required String userId,
    required List<String> itemIds,
  }) async {
    try {
      final data = await api.getUserData(userId: userId, itemIds: itemIds);
      _changed.addAll(data);
      notifyListeners();
    } on JellyfinException {
      // Pas grave
    }
  }
}
