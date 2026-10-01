import 'package:shared_preferences/shared_preferences.dart';

import '../models/genre.dart';

/// Tri choisi pour la grille des films et celle des séries, retenu sur le
/// téléphone.
class LibraryPreferences {
  static String _key(String itemType) => 'library_sort_$itemType';

  Future<LibrarySort> loadSort(String itemType) async {
    final prefs = await SharedPreferences.getInstance();
    return LibrarySort.fromName(prefs.getString(_key(itemType)));
  }

  Future<void> saveSort(String itemType, LibrarySort sort) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(itemType), sort.name);
  }
}
