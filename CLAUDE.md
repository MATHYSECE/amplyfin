# Amplyfin

Client Jellyfin en Flutter (films, séries, téléchargements hors ligne, profils).
Plateformes existantes : Android (téléphone, tablette), Fire TV / Android TV,
iPhone / iPad (fabriqué sur Codemagic, voir `codemagic.yaml`, puis signé avec
Sideloadly).

## Objectif en cours : l'appli Windows

Je veux une version Windows d'Amplyfin, d'abord pour mon PC portable. Le travail se
fait sur la branche `windows`.

Ce qui reste à faire, dans l'ordre :

1. ~~Ajouter la plateforme Windows~~ (fait : dossier `windows/`, nom
   « Amplyfin », icône générée depuis `assets/icon/icon.png`).
2. ~~Adapter le code qui suppose un téléphone~~ (fait) : appareil
   « Windows » pour le serveur, décodage par la carte graphique
   (`d3d11va`), volume du lecteur à la molette (retenu), pas de luminosité,
   pas de réglage « données mobiles » ni de demande de notifications,
   « PC » au lieu de « téléphone » dans les textes. Repère :
   `DeviceCapabilities.isDesktop` (réglé au démarrage, faux dans les tests).
   Mouvement saccadé des films à 24 images/s sur écran 60 Hz : corrigé par
   le lissage de mpv (`_smoothMotion` dans `player_screen.dart`). Vérifié
   sur une 4K HEVC 10 bits (portable Ryzen 5 5500U) : `d3d11va-copy`, peu
   d'images perdues. Le PC ne dit pas ce qu'il sait décoder (tous les
   formats sont essayés en direct).
3. Rendre l'appli agréable à la souris et au clavier : plein écran (F11,
   double-clic), espace = pause, flèches = avancer/reculer, molette = volume,
   curseur caché pendant la lecture, survols, taille minimale de fenêtre. La
   navigation au clavier de la télé (`lib/widgets/tv_focus.dart`) peut servir
   de base.
4. Fabriquer la version finale : `flutter build windows --release`
   (dossier `build/windows/x64/runner/Release/`).

Les changements pour Windows ne doivent rien casser sur Android, iPhone et
Fire TV : on teste la plateforme (`Platform.isWindows`, `defaultTargetPlatform`)
au lieu de modifier le comportement existant.

## Sur le PC portable

Ce PC ne sert qu'au développement de l'appli Windows. Seuls Flutter (même
version que sur le PC fixe, 3.47.5, dans `%USERPROFILE%\dev\flutter`) et
Visual Studio 2022 Build Tools (C++, avec le composant ATL demandé par
`flutter_secure_storage`) y sont installés. Le mode développeur de Windows
est activé (liens symboliques des extensions). Flutter est réglé pour
Windows uniquement (Android, iOS, web désactivés avec `flutter config`).
On ne travaille pas ici sur Android, iPhone ou Fire TV, sauf si c'est
nécessaire ; ces plateformes se fabriquent sur le PC fixe ou sur Codemagic.

Pièges connus :

- `dart run flutter_launcher_icons` régénère aussi les icônes Android et
  iPhone : annuler ces changements-là (`git checkout android ios`).
- Garder le `pubspec.lock` du PC fixe (`flutter pub get --enforce-lockfile`)
  pour avoir les mêmes versions des bibliothèques partout.

Commandes utiles :

- `flutter run -d windows` : lancer l'appli
- `flutter test` : tests (dossier `test/`)
- `flutter analyze` : vérifications du code

## Façon de travailler

- Tout est écrit en français : commentaires, textes de l'appli, messages de
  commit. Commentaires simples, sans jargon, qui expliquent le « pourquoi ».
- Code organisé en `lib/api` (appels Jellyfin), `lib/models`, `lib/services`,
  `lib/screens`, `lib/widgets`, `lib/theme`.
- Commits courts par étape, titre du type « Sujet, étape N : ce qui change »,
  puis un paragraphe qui décrit le comportement obtenu.
