import 'dart:ui' show Color;

/// Aperçus flous des images (« BlurHash ») : le serveur envoie, pour chaque
/// image, un petit texte qui décrit ses couleurs. On l'affiche tout de suite
/// en flou, le temps que la vraie image arrive.

/// Aperçu de l'image [type] (« Primary », « Backdrop »…) d'empreinte [tag],
/// lu dans `ImageBlurHashes` d'un élément du serveur. Null s'il n'y en a
/// pas (le serveur les range par type, puis par empreinte d'image).
String? blurHashOf(Map<String, dynamic> json, String type, String? tag) {
  if (tag == null) return null;
  final hashes = json['ImageBlurHashes'];
  if (hashes is! Map<String, dynamic>) return null;
  final byTag = hashes[type];
  if (byTag is! Map<String, dynamic>) return null;
  final hash = byTag[tag];
  return hash is String && hash.length >= 6 ? hash : null;
}

const _digits =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    '#\$%*+,-.:;=?@[]^_{|}~';

/// Couleur moyenne de l'image décrite par [hash] (les caractères 3 à 6 de
/// l'aperçu), ou null si l'aperçu est illisible. Sert au halo de couleur
/// des fiches (ambilight).
Color? blurHashAverageColor(String hash) {
  if (hash.length < 6) return null;
  var value = 0;
  for (final char in hash.substring(2, 6).split('')) {
    final digit = _digits.indexOf(char);
    if (digit < 0) return null;
    value = value * 83 + digit;
  }
  return Color(0xFF000000 | (value & 0xFFFFFF));
}
