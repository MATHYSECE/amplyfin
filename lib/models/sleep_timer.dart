/// Choix de la minuterie de sommeil du lecteur : la lecture se met en pause
/// toute seule après un moment, ou à la fin de la vidéo en cours.
enum SleepChoice {
  off('Désactivée'),
  minutes15('15 minutes', Duration(minutes: 15)),
  minutes30('30 minutes', Duration(minutes: 30)),
  minutes45('45 minutes', Duration(minutes: 45)),
  hour('1 heure', Duration(hours: 1)),
  endOfVideo('À la fin de la vidéo');

  const SleepChoice(this.label, [this.delay]);

  final String label;

  /// Durée avant la pause (null : pas de durée fixe).
  final Duration? delay;
}

/// Réglage actuel, pour la ligne du menu : « Désactivée », « À la fin de
/// la vidéo », ou « Pause dans 12 min » ([pauseAt] : heure prévue de la
/// pause).
String sleepTimerStatus(SleepChoice choice, DateTime? pauseAt, DateTime now) {
  if (choice.delay == null || pauseAt == null) return choice.label;
  final left = pauseAt.difference(now);
  if (left <= const Duration(minutes: 1)) return 'Pause dans moins d\'1 min';
  // Arrondi à la minute du dessus : « 15 min » juste après le réglage
  return 'Pause dans ${(left.inSeconds / 60).ceil()} min';
}
