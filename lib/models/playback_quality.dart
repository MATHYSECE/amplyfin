/// Qualité de lecture choisie dans le lecteur.
class PlaybackQuality {
  const PlaybackQuality(this.label, {this.maxBitrate, this.maxWidth});

  /// Texte affiché dans le menu « Qualité ».
  final String label;

  /// Débit maximum en bits/s, ou null pour la qualité originale
  /// (fichier lu tel quel, sans conversion).
  final int? maxBitrate;

  /// Largeur d'image maximum en pixels (null = pas de limite).
  /// Sans elle, le serveur garderait la définition d'origine dès que le
  /// fichier respecte déjà le débit demandé.
  final int? maxWidth;

  bool get isOriginal => maxBitrate == null;

  static const original = PlaybackQuality('Originale');

  /// Choix proposés.
  static const all = [
    original,
    PlaybackQuality('1080p · 20 Mb/s', maxBitrate: 20000000, maxWidth: 1920),
    PlaybackQuality('720p · 8 Mb/s', maxBitrate: 8000000, maxWidth: 1280),
    PlaybackQuality('480p · 3 Mb/s', maxBitrate: 3000000, maxWidth: 854),
  ];
}
