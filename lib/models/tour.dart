/// Contenu de la visite guidée (et de l'astuce du lecteur), selon
/// l'appareil : gestes au doigt, télécommande, ou souris et clavier.
library;

/// Façon d'utiliser l'appareil.
enum TourDevice {
  /// Téléphone ou tablette : au doigt.
  touch,

  /// Télé : à la télécommande (pas de téléchargements).
  tv,

  /// PC : souris et clavier.
  desktop,
}

/// Illustration d'une page.
enum TourScene { welcome, resume, details, downloads, player, profiles }

/// Une page de la visite.
class TourPage {
  const TourPage(this.scene, this.title, this.text);

  final TourScene scene;
  final String title;
  final String text;
}

/// Les pages de la visite pour [device] (pas de téléchargements sur télé).
List<TourPage> tourPages(TourDevice device) => [
  const TourPage(
    TourScene.welcome,
    'Bienvenue sur Amplyfin',
    'Tes films et séries sont lus tels quels : 4K, HDR et son d\'origine. '
        'En haut du lecteur, une mention te dit toujours ce qui se passe.',
  ),
  TourPage(TourScene.resume, 'Reprends là où tu t\'es arrêté', switch (device) {
    TourDevice.touch =>
      'Un appui relance la lecture. Un appui long ouvre les options : '
          'télécharger, marquer comme vu ou retirer de la rangée.',
    TourDevice.tv =>
      'OK relance la lecture. OK maintenu ouvre les options : marquer '
          'comme vu ou retirer de la rangée.',
    TourDevice.desktop =>
      'Un clic relance la lecture. Un clic droit ouvre les options : '
          'télécharger, marquer comme vu ou retirer de la rangée.',
  }),
  const TourPage(
    TourScene.details,
    'Chaque série garde tes langues',
    'Choisis l\'audio et les sous-titres une fois : ils sont retenus pour '
        'toute la série. Chaque épisode indique sa durée, sa taille et sa '
        'qualité.',
  ),
  if (device != TourDevice.tv)
    TourPage(
      TourScene.downloads,
      'Emporte tes films partout',
      'Télécharge un film, un épisode ou une saison entière, en qualité '
          'd\'origine. Ils se lisent sans connexion, et ta progression '
          'rejoint le serveur au retour du réseau.'
          '${device == TourDevice.touch ? ' En Wi-Fi par défaut.' : ''}',
    ),
  TourPage(
    TourScene.player,
    switch (device) {
      TourDevice.touch => 'Le lecteur, au bout des doigts',
      TourDevice.tv => 'Tout se fait à la télécommande',
      TourDevice.desktop => 'Souris et clavier',
    },
    switch (device) {
      TourDevice.touch =>
        'Un appui affiche les commandes. À la fin d\'un épisode, le suivant '
            'se lance tout seul après 10 secondes.',
      TourDevice.tv =>
        'Un contour blanc montre toujours ce qui est sélectionné. À la fin '
            'd\'un épisode, le suivant se lance tout seul après 10 secondes.',
      TourDevice.desktop =>
        'Bouge la souris pour afficher les commandes du lecteur. Ailleurs, '
            'Échap ou le bouton « précédent » de la souris revient en arrière.',
    },
  ),
  const TourPage(
    TourScene.profiles,
    'Un profil pour chacun',
    'Chaque personne garde ses reprises, ses recherches et ses langues. '
        'Change de profil depuis le menu Compte. La visite se revoit à tout '
        'moment dans Paramètres.',
  ),
];

/// Une commande et ce qu'elle fait (lecteur : télécommande ou clavier).
typedef TourKey = ({String key, String action});

/// Commandes du lecteur à la télécommande.
const tvPlayerKeys = <TourKey>[
  (key: 'OK', action: 'Lecture / pause, ouvrir'),
  (key: 'OK maintenu', action: 'Les options (comme un appui long)'),
  (
    key: 'Gauche / droite',
    action: '−10 s / +10 s ; maintenues : avance rapide',
  ),
  (key: 'Haut / bas, Menu', action: 'Afficher les commandes'),
  (key: 'Retour', action: 'Masquer les commandes, puis quitter'),
];

/// Commandes du lecteur au clavier.
const desktopPlayerKeys = <TourKey>[
  (key: 'Espace', action: 'Lecture / pause (ou K, ou un clic)'),
  (key: 'F', action: 'Plein écran (ou double clic) ; Échap pour en sortir'),
  (key: '← →', action: '−10 s / +10 s'),
  (key: '↑ ↓', action: 'Volume (ou la molette) ; M pour couper le son'),
];
