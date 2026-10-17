<div align="center">

<img src="assets/icon/icon.png" alt="Icône d'Amplyfin" width="120">

# Amplyfin

**Le client Jellyfin qui lit tout, partout, sans prise de tête.**

Films et séries de ton serveur Jellyfin sur téléphone, tablette, télé et PC :
fichier d'origine en 4K HDR, le moins de conversion possible, une interface
sobre en noir et blanc.

[![Dernière version](https://img.shields.io/github/v/release/MATHYSECE/amplyfin?label=version&color=white&labelColor=black)](https://github.com/MATHYSECE/amplyfin/releases/latest)
![Android](https://img.shields.io/badge/Android-téléphone%20·%20tablette-black?logo=android&logoColor=white)
![Fire TV](https://img.shields.io/badge/Fire%20TV-télécommande-black?logo=amazonfiretv&logoColor=white)
![iPhone](https://img.shields.io/badge/iPhone%20·%20iPad-iOS%2015+-black?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-10%20·%2011-black?logo=windows&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-3.47-black?logo=flutter&logoColor=white)

[**Télécharger**](https://github.com/MATHYSECE/amplyfin/releases/latest) ·
[Fonctionnalités](#fonctionnalités) ·
[Installation](#installation) ·
[Développement](#développement)

</div>

---

## Pourquoi Amplyfin ?

Les applis existantes convertissent souvent la vidéo sans prévenir, perdent la
4K ou le HDR, affichent mal les sous-titres ou se comportent différemment
d'un appareil à l'autre. Amplyfin part du principe inverse :

- **Le fichier d'origine d'abord.** La vidéo est lue telle quelle, 4K et HDR
  compris. Le serveur ne convertit que ce que l'appareil ne sait vraiment pas
  lire, et l'appli le dit clairement.
- **Le meilleur lecteur sur chaque appareil.** Plutôt qu'un seul moteur
  partout, chaque plateforme utilise celui qui lit le mieux sur sa puce.
- **Une seule appli, la même partout.** Téléphone, tablette, télé et PC
  partagent la même base de code et les mêmes réglages.

## Fonctionnalités

### Lecture
- Lecture directe du fichier d'origine : **4K, HDR10, HEVC 10 bits**, sans
  conversion.
- Mention claire en haut du lecteur : `ORIGINAL`, `SON CONVERTI` (image
  d'origine, seul le son est adapté) ou `CONVERTI`.
- Si la lecture directe est impossible, une fenêtre **explique pourquoi** et
  demande avant de convertir.
- Menu **Qualité** pour demander un flux plus léger (connexion lente).
- **Pistes audio et sous-titres** changeables en cours de lecture, avec la
  **taille des sous-titres** réglable.
- Langues préférées enregistrées sur ton compte Jellyfin, et retenues
  **série par série**.

### Séries
- **Reprise** à l'endroit exact où tu t'étais arrêté.
- Bouton **« Passer l'intro »** (avec le plugin Intro Skipper sur le serveur),
  jamais de saut automatique.
- Carte **« Épisode suivant »** avec compte à rebours, et
  **« Tu regardes toujours ? »** après trois épisodes enchaînés.

### Prise en main
- **Visite guidée** à la première connexion de chaque profil, adaptée à
  l'appareil (gestes, télécommande, souris et clavier), à revoir dans
  Paramètres.
- **Astuce** à la première lecture : les gestes ou les touches du lecteur.

### Partout, même hors ligne
- **Téléchargements** du fichier d'origine sur téléphone et tablette (Wi-Fi
  par défaut), lus sans connexion ; la position est renvoyée au serveur au
  retour du réseau.
- **Profils** : chaque membre de la famille garde son compte, ses reprises,
  ses recherches et ses langues. Écran **« Qui regarde ? »** sur télé et
  tablette.
- Bandeau discret quand le serveur est injoignable, sans perdre l'écran en
  cours.

### Sur chaque appareil
| Appareil | Ce qui change |
|---|---|
| **Téléphone** | Gestes : double appui pour ±10 s, glisser pour la luminosité et le volume. |
| **Tablette** | Mise en page adaptée, « Qui regarde ? » à l'ouverture. |
| **Fire TV** | Tout à la télécommande : sélection visible, OK maintenu pour les options, avance rapide en maintenant les flèches. |
| **PC Windows** | Souris et clavier : plein écran (F, F11, double clic), espace, flèches, molette pour le volume, survol des affiches. |

## Les lecteurs vidéo

| Appareil | Lecteur | Pourquoi |
|---|---|---|
| Android (téléphone, tablette, Fire TV) | **ExoPlayer** | Le lecteur d'Android (celui de Plex, Netflix, YouTube) : il parle directement à la puce vidéo. |
| iPhone, iPad | **mpv** | Lit le MKV, le DTS et les sous-titres avancés, que le lecteur d'Apple refuse. Décodage par la puce de l'iPhone. |
| Windows | **mpv** | La référence sur PC. Décodage par la carte graphique (D3D11), lissage des films à 24 images/s. |

Ce que chaque appareil sait décoder est mesuré sur l'appareil lui-même et
envoyé au serveur : la page **Paramètres → « Ce que l'appareil sait lire »**
l'affiche.

## Installation

Toutes les versions sont sur la page
[**Releases**](https://github.com/MATHYSECE/amplyfin/releases/latest).

<details>
<summary><b>Android (téléphone, tablette)</b></summary>

1. Télécharge `Amplyfin-x.y.z.apk` sur le téléphone.
2. Ouvre-le et autorise l'installation depuis cette source si Android le
   demande.
3. Les mises à jour s'installent par-dessus, sans rien perdre.

Android 7 ou plus récent.
</details>

<details>
<summary><b>Fire TV</b></summary>

1. Sur la Fire TV : Paramètres → Ma Fire TV → Options pour les développeurs →
   autorise les applis de sources inconnues pour l'appli **Downloader**
   (gratuite, dans l'Appstore).
2. Dans Downloader, saisis l'adresse de `Amplyfin-x.y.z-tv.apk` (page
   Releases) et installe-le.

L'apk `-tv` fonctionne aussi sur les téléphones et sur les Android 32 bits.
Les Fire TV récentes sous Vega OS ne lisent pas les applis Android.
</details>

<details>
<summary><b>PC Windows</b></summary>

1. Télécharge `Amplyfin-x.y.z-installation.exe` et lance-le.
2. Si Windows affiche « Windows a protégé votre ordinateur » : clique sur
   **Informations complémentaires** puis **Exécuter quand même** (l'appli
   n'est pas signée par un éditeur payant).
3. Aucun droit administrateur n'est nécessaire. Une mise à jour s'installe
   par-dessus, en gardant comptes et réglages.

Windows 10 ou 11, 64 bits.
</details>

<details>
<summary><b>iPhone, iPad</b></summary>

L'appli iPhone est fabriquée sans Mac, sur
[Codemagic](https://codemagic.io) (workflow `ios-sans-signature` de
`codemagic.yaml`), puis installée avec
[Sideloadly](https://sideloadly.io) et un identifiant Apple gratuit.
L'installation est à renouveler tous les 7 jours (limite d'Apple pour les
comptes gratuits).

iOS 15 ou plus récent.
</details>

### Côté serveur
- Un serveur **Jellyfin** accessible depuis l'appareil (testé avec Jellyfin
  12.1). L'adresse se saisit dans l'appli au premier lancement.
- Facultatif : le plugin **Intro Skipper** pour le bouton « Passer l'intro ».

## Développement

### Prérequis
- [Flutter](https://docs.flutter.dev/get-started/install) 3.47
- Android : Android Studio (SDK et émulateur)
- Windows : Visual Studio 2022 Build Tools (C++ et composant ATL), mode
  développeur de Windows activé, [Inno Setup 6](https://jrsoftware.org/isinfo.php)
  pour l'installateur
- iPhone : aucun Mac nécessaire, tout se fait sur Codemagic

### Commandes utiles
```bash
flutter pub get
flutter run                 # appareil ou émulateur branché
flutter run -d windows      # version PC
flutter analyze             # vérifications du code
flutter test                # tests
```

Fabriquer les versions à distribuer :
```bash
# Android, téléphone (64 bits)
flutter build apk --release --target-platform android-arm64
# Android, Fire TV et 32 bits
flutter build apk --release --target-platform android-arm,android-arm64
# Windows : appli + installateur dans dist\
powershell -ExecutionPolicy Bypass -File windows\installer\build.ps1
```
Les apk de mise à jour doivent être signés avec la même clé
(`android/key.properties`, hors du dépôt) et porter un numéro de version
plus grand (`version:` dans `pubspec.yaml`).

### Organisation du code
```
lib/
├── api/        appels au serveur Jellyfin et profil de l'appareil
├── models/     données (pistes, sous-titres SRT, formats lisibles…)
├── services/   session, téléchargements, profils, moteurs vidéo
│   ├── video_engine.dart   lecteur générique utilisé par tout l'écran de lecture
│   ├── exo_engine.dart     ExoPlayer (Android)
│   └── mpv_engine.dart     mpv (iPhone, iPad, Windows)
├── screens/    écrans (accueil, fiches, lecteur, paramètres…)
├── theme/      couleurs, polices (Manrope), arrondis
└── widgets/    morceaux d'écran réutilisés (affiches, commandes du lecteur…)
```

Principes du code :
- tous les appels au serveur passent par `lib/api/jellyfin_api.dart` ;
- l'adresse du serveur est toujours saisie dans l'appli, jamais écrite dans
  le code ; le jeton de connexion est gardé dans le coffre-fort du système
  (`flutter_secure_storage`), le mot de passe n'est jamais stocké ;
- tout le style passe par le thème central (`lib/theme`).

## Feuille de route
- [x] Téléphone et tablette Android, iPhone, iPad
- [x] Fire TV (navigation à la télécommande)
- [x] Profils
- [x] Windows
- [x] Lecteur ExoPlayer sur Android
- [x] Améliorations (téléchargements, Continuer à regarder, synchronisation)
- [x] Visite guidée à la première connexion
- [ ] Télés Samsung (Tizen, lecteur AVPlay)

---

<div align="center">
<sub>Amplyfin est un projet personnel, indépendant du projet Jellyfin.</sub>
</div>
