import 'package:flutter/foundation.dart';

import '../api/jellyfin_api.dart';

/// « Ma liste » : retient les ajouts et retraits faits depuis l'appli, pour
/// que le cœur des fiches et la rangée de l'accueil se mettent à jour sans
/// tout recharger.
class FavoriteState extends ChangeNotifier {
  FavoriteState._();

  static final instance = FavoriteState._();

  /// État après un changement, par identifiant (film ou série).
  final _changed = <String, bool>{};

  /// Vrai si l'élément est dans la liste : le dernier changement, sinon ce
  /// qu'a dit le serveur ([fallback]).
  bool of(String itemId, {required bool fallback}) =>
      _changed[itemId] ?? fallback;

  /// Changement de profil : la liste retenue était celle de l'autre personne.
  void reset() {
    _changed.clear();
    notifyListeners();
  }

  /// Ajoute [itemId] à la liste (ou l'en retire) sur le serveur.
  Future<void> set(
    JellyfinApi api, {
    required String userId,
    required String itemId,
    required bool favorite,
  }) async {
    await api.setFavorite(userId: userId, itemId: itemId, favorite: favorite);
    _changed[itemId] = favorite;
    notifyListeners();
  }
}
