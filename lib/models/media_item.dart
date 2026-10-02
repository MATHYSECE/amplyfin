import 'watch_progress.dart';

/// Un élément de la bibliothèque (film ou série), avec juste ce qu'il faut
/// pour la grille d'affiches.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    this.type,
    this.year,
    this.posterTag,
    this.progress = const WatchProgress(),
  });

  /// Lit un élément à partir du JSON renvoyé par GET /Items.
  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] as Map<String, dynamic>?;
    return MediaItem(
      id: json['Id'] as String,
      name: (json['Name'] as String?) ?? 'Sans titre',
      type: json['Type'] as String?,
      year: json['ProductionYear'] as int?,
      posterTag: imageTags?['Primary'] as String?,
      progress: WatchProgress.fromUserData(
        json['UserData'] as Map<String, dynamic>?,
      ),
    );
  }

  /// Identifiant sur le serveur.
  final String id;

  /// Titre affiché.
  final String name;

  /// Type d'élément pour le serveur : « Movie », « Series »…
  final String? type;

  /// Année de sortie (peut manquer).
  final int? year;

  /// Empreinte de l'affiche : change quand l'affiche change sur le serveur.
  /// Null s'il n'y a pas d'affiche.
  final String? posterTag;

  /// Vu ou pas, et pour une série le nombre d'épisodes pas vus (seulement
  /// si la demande au serveur l'inclut).
  final WatchProgress progress;

  bool get isSeries => type == 'Series';
}

/// Une « page » d'éléments, et le nombre total d'éléments sur le serveur.
class ItemPage {
  const ItemPage({required this.items, required this.totalCount});

  final List<MediaItem> items;
  final int totalCount;
}
