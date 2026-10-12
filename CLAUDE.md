# Amplyfin

Client Jellyfin en Flutter (films, séries, téléchargements hors ligne, profils).
Plateformes existantes : Android (téléphone, tablette), Fire TV / Android TV,
iPhone / iPad (fabriqué sur Codemagic, voir `codemagic.yaml`, puis signé avec
Sideloadly).

## Objectif en cours : l'appli Windows

Je veux une version Windows d'Amplyfin, d'abord pour mon PC portable. Il n'y a
pas encore de dossier `windows/` : il se crée avec
`flutter create --platforms=windows .`.

Ce qui reste à faire, dans l'ordre :

1. Ajouter la plateforme Windows (dossier `windows/`, nom « Amplyfin »,
   icône à partir de `assets/icon/`).
2. Adapter le code qui suppose un téléphone :
   - `lib/api/jellyfin_api.dart` : l'en-tête `Device=` envoie « Android » hors
     iPhone → envoyer « Windows ».
   - `lib/screens/player_screen.dart` (`_videoConfiguration`) : décodage
     matériel réglé seulement pour Android → `hwdec` adapté à Windows
     (d3d11va) pour la HEVC 10 bits et la 4K.
   - `lib/widgets/player_controls.dart` : luminosité et volume réglés par
     glissement du doigt → pas de luminosité sur PC, volume propre au lecteur.
   - `lib/services/device_capabilities.dart` : le canal `amplyfin/device`
     n'existe que sur Android et iPhone (tout est accepté par défaut) ;
     vérifier ce que le PC sait lire sans conversion.
   - `lib/services/download_manager.dart` : pas de demande d'autorisation pour
     les notifications ; vérifier le dossier des téléchargements.
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
Visual Studio 2022 Build Tools (C++) y sont installés. Flutter est réglé pour
Windows uniquement (Android, iOS, web désactivés avec `flutter config`).
On ne travaille pas ici sur Android, iPhone ou Fire TV, sauf si c'est
nécessaire ; ces plateformes se fabriquent sur le PC fixe ou sur Codemagic.

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
