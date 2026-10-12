# Appli Windows : compte rendu du PC portable

À l'attention de Claude sur le PC fixe (le QG du projet). Ce fichier
résume le travail fait le 12 octobre 2026 sur le PC portable, pour que tu
puisses reprendre sans relire toute la session.

## En bref

- Amplyfin tourne maintenant sur **Windows** : lecture vidéo par la carte
  graphique, souris et clavier, plein écran, installateur.
- Tout est sur la branche **`windows`** (7 commits au-dessus de `main`,
  rien de fusionné). `main` n'a pas bougé.
- Installateur publié en **pré-version GitHub** pour être essayé sur le PC
  d'un ami : https://github.com/MATHYSECE/amplyfin/releases/tag/windows-v1.0.0
- **Android, iPhone et Fire TV ne doivent rien voir changer** : chaque
  nouveauté est réservée au PC. Rien n'a pu être essayé sur ces appareils
  depuis le portable (pas d'outils Android / iOS installés) : à vérifier
  ici avant de fusionner.

## Les commits (branche `windows`)

| Commit | Contenu |
|---|---|
| `254f0f8` Étape 0 | `CLAUDE.md` décrivant l'objectif Windows (voir « CLAUDE.md » plus bas) |
| `d3791b5` Étape 1 | Dossier `windows/` (créé par Flutter), nom « Amplyfin », icône `.ico` |
| `86765c0` Étape 2 | Ce qui supposait un téléphone (détails plus bas) |
| `9a0eef0` Lecteur | Mouvement lissé des films à 24 images/s |
| `f44ee59` Étape 3 | Souris, clavier, plein écran, survols |
| `c8179b0` Fluidité | Pas de flou en arrière-plan sur PC |
| `2960130` Étape 4 | Installateur (Inno Setup) |

## Ce qui a changé, et pourquoi

### Repère « on est sur PC »
`DeviceCapabilities.isDesktop` (`lib/services/device_capabilities.dart`),
réglé au démarrage par `detectDesktop()` dans `main.dart`
(`Platform.isWindows`). C'est un champ et non un test direct de la
plateforme pour que **les tests restent en mode téléphone** même lancés sur
un PC Windows (comme `isTv`). `deviceWord` donne « PC » ou « téléphone »
pour les textes (« effacé du PC »).

### Étape 2 : ce qui supposait un téléphone
- `jellyfin_api.dart` : en-tête `Device="Windows"` (avant : « Android »).
- `player_screen.dart` : `hwdec: 'd3d11va,dxva2,auto'` sur Windows.
  Mesuré : `d3d11va-copy` sur une 4K HEVC 10 bits, sans images perdues.
- `player_controls.dart` : pas de luminosité ni de glissement sur PC ; la
  molette règle le **volume du lecteur** (pas celui de Windows), retenu
  dans `PlayerPreferences` (`player_volume`).
- Téléchargements : pas de demande de notifications, réglage « données
  mobiles » masqué sur PC (sans effet sur ordinateur), message de
  confirmation adapté.
- Le PC ne dit pas ce qu'il sait décoder (le canal `amplyfin/device`
  n'existe pas sous Windows) : tout est accepté en lecture directe, comme
  le prévoyait déjà le code. L'écran « Ce que l'appareil sait lire »
  affiche « Réponse du PC impossible ».

### Lecteur : films à 24 images/s
Sur un écran à 60 Hz, un film à 23,976 images/s montre ses images tour à
tour 3 puis 2 fois : saccade légère (l'utilisateur la voyait sur GoT S4E10).
`_smoothMotion()` dans `player_screen.dart`, Windows seulement :
`display-fps-override` = fréquence de l'écran (lue par Flutter, 60 par
défaut), `video-sync=display-resample`, `interpolation=yes`,
`tscale=oversample`. Vérifié avec un relevé des propriétés de mpv
(`display-sync-active=yes`) ; nettement plus fluide selon l'utilisateur.

### Étape 3 : souris et clavier
- **Plein écran** : canal natif `amplyfin/window` écrit dans
  `windows/runner/flutter_window.cpp` (sans bordure, sur tout l'écran,
  retour à la place d'avant), côté Dart `lib/services/app_window.dart`.
  Aucune bibliothèque ajoutée. Fenêtre de 720 × 480 au minimum
  (`WM_GETMINMAXINFO`).
- **Lecteur sur PC** : souris qui bouge = commandes et curseur affichés
  (cachés ensemble) ; clic = lecture / pause ; double clic, F, F11 = plein
  écran (bouton aussi en haut) ; Échap quitte le plein écran mais jamais le
  lecteur ; espace / K ; ←/→ = 10 s ; ↑/↓ et molette = volume ; M = muet.
  Après un clic sur un bouton, le clavier revient au lecteur.
- **Ailleurs** : `PressableScale` (`lib/widgets/ui.dart`) grossit au survol
  avec un curseur en main, clic droit = appui long (options) ; Échap et le
  bouton « précédent » de la souris = retour (`_DesktopBack` dans
  `main.dart`).

### Fluidité du défilement
Relevés du temps de dessin de chaque image (supprimés depuis) :
- les **flous en arrière-plan** (`BackdropFilter` des barres du haut et du
  bas, en-têtes) coûtaient cher sur la puce graphique intégrée. Nouveau
  widget `FrostedBlur` : flou sur téléphone / tablette / télé, simple voile
  sombre sur PC ;
- **Impeller essayé puis abandonné** : défilement à peine meilleur, mais
  vidéo 4K à 20–40 ms par image. On garde Skia (le moteur par défaut).
- Restent de petits à-coups au premier passage sur une page (arrivée des
  affiches). Défilement doux à la molette : **refusé par l'utilisateur**.

### Étape 4 : installateur
`windows/installer/build.ps1` fabrique l'appli puis
`dist\Amplyfin-<version>-installation.exe` avec Inno Setup 6
(`windows/installer/amplyfin.iss`, en français). Installation pour la
personne seule, sans droits administrateur
(`%LOCALAPPDATA%\Programs\Amplyfin`), menu Démarrer, bibliothèques C++ de
Microsoft jointes. **Ne jamais changer l'`AppId`** (sinon les mises à jour
ne remplacent plus l'ancienne installation). Mise à jour : changer
`version:` dans `pubspec.yaml`, relancer le script, installer par-dessus.

## Points d'attention pour toi

1. **CLAUDE.md** : celui du PC fixe n'a jamais été poussé, celui de la
   branche `windows` a été écrit sur le portable sans le voir. En
   fusionnant, **garde le tien comme base** et ajoute-y la partie Windows
   (objectif, étapes faites, pièges, outils du portable) ; ne l'écrase pas.
2. **`pubspec.lock` inchangé** : `flutter create` avait changé des versions
   de bibliothèques, c'est annulé. `pubspec.yaml` a seulement gagné la
   section `windows:` de `flutter_launcher_icons`.
3. **Icônes** : `dart run flutter_launcher_icons` régénère aussi Android et
   iPhone (un fichier Android et le projet Xcode bougeaient) ; ces
   changements ont été annulés. À refaire de même si tu relances l'outil.
4. **À vérifier sur téléphone, tablette et Fire TV** avant de fusionner :
   textes des téléchargements (« téléphone » désormais calculé), lecteur
   (gestes, luminosité, volume du système), barres floutées (`FrostedBlur`),
   `PressableScale` (appui long), retour sur télé. Les 223 tests passent
   (dont `test/desktop_test.dart`, nouveau).
5. **Pas essayé** : cartes graphiques NVIDIA / Intel, autre écran que
   60 Hz, PC sans les bibliothèques C++ (l'essai chez l'ami le dira).
6. Codemagic (`codemagic.yaml`, iPhone) n'est pas concerné.

## Outils installés sur le portable

Flutter 3.47.5 (comme ici, dans `%USERPROFILE%\dev\flutter`, réglé pour
Windows seulement), Visual Studio 2022 Build Tools (C++ et composant **ATL**,
demandé par `flutter_secure_storage`), mode développeur de Windows, Inno
Setup 6, GitHub CLI (`gh`, connecté au compte MATHYSECE). Pour fabriquer
l'appli Windows sur le PC fixe, il faudrait les mêmes (sauf `gh`).

## Pour fusionner

```bash
git fetch origin
git switch windows
flutter test
```

Puis vérifier les points 1 et 4, et fusionner `windows` dans `main` (ou
ouvrir une pull request : https://github.com/MATHYSECE/amplyfin/pull/new/windows).
