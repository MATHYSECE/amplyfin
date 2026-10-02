import 'durations.dart';

/// Où en est la lecture d'un film ou d'un épisode, d'après le serveur
/// (partie « UserData » : la même dans toutes les applis Jellyfin).
/// Le serveur ne retient une position qu'au-delà de 5 % de la vidéo ;
/// au-delà de 90 %, il la considère comme vue et oublie la position.
class WatchProgress {
  const WatchProgress({
    this.position = Duration.zero,
    this.percentage = 0,
    this.played = false,
    this.lastPlayed,
    this.unplayedCount,
  });

  /// Lit la partie « UserData » d'un élément (absente : rien de commencé).
  factory WatchProgress.fromUserData(Map<String, dynamic>? userData) {
    if (userData == null) return const WatchProgress();
    return WatchProgress(
      position:
          ticksToDuration(userData['PlaybackPositionTicks'] as int?) ??
          Duration.zero,
      percentage: (userData['PlayedPercentage'] as num?)?.toDouble() ?? 0,
      played: userData['Played'] == true,
      lastPlayed: DateTime.tryParse(
        (userData['LastPlayedDate'] as String?) ?? '',
      ),
      unplayedCount: userData['UnplayedItemCount'] as int?,
    );
  }

  /// Position où la lecture s'est arrêtée.
  final Duration position;

  /// Part déjà vue, de 0 à 100.
  final double percentage;

  /// Vrai si le film ou l'épisode a été vu jusqu'au bout.
  final bool played;

  /// Dernière lecture, sur n'importe quel appareil (null si jamais lu).
  final DateTime? lastPlayed;

  /// Série ou saison : nombre d'épisodes pas encore vus (null : inconnu,
  /// ou film).
  final int? unplayedCount;

  /// Vrai si la lecture peut reprendre là où elle s'était arrêtée.
  bool get canResume => position > Duration.zero;

  /// Part déjà vue, de 0 à 1 (pour les barres de progression).
  double get fraction => (percentage / 100).clamp(0.0, 1.0);

  /// Texte du bouton : « Reprendre à 42:17 ».
  String get resumeLabel => 'Reprendre à ${formatPosition(position)}';

  /// Temps qu'il reste à voir : « Reste 14 min » (null si durée inconnue).
  String? remainingLabel(Duration? runtime) {
    if (runtime == null) return null;
    final left = formatRuntime(runtime - position);
    return left == null ? null : 'Reste $left';
  }
}
