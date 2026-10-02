/// Message brut du moteur vidéo, rendu présentable pour le « Détail » d'une
/// erreur (diagnostic) : il peut contenir l'adresse du serveur et la clé de
/// connexion, qu'on ne montre jamais.
library;

final _url = RegExp(r'[a-z][a-z0-9+.-]*://\S+', caseSensitive: false);
final _secret = RegExp(
  r'(api_?key|token|access_?token)=[^\s&"]+',
  caseSensitive: false,
);

/// Retire les adresses et les clés du message [text].
String cleanPlayerMessage(String text) => text
    .replaceAll(_url, '[adresse]')
    .replaceAllMapped(_secret, (m) => '${m[1]}=…')
    .trim();
