/// Petits outils pour les durées.
library;

/// Jellyfin compte les durées en « ticks » : 10 millions par seconde.
Duration? ticksToDuration(int? ticks) =>
    ticks == null ? null : Duration(microseconds: ticks ~/ 10);

/// L'inverse : une durée en « ticks » (pour les signalements au serveur).
int durationToTicks(Duration duration) => duration.inMicroseconds * 10;

/// Position dans une vidéo, façon chronomètre : « 12:58 » ou « 1:05:09 ».
String formatPosition(Duration position) {
  final total = position.isNegative ? 0 : position.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}

/// Durée lisible : « 2 h 04 », « 1 h » ou « 45 min ».
String? formatRuntime(Duration? duration) {
  if (duration == null || duration.inSeconds <= 0) return null;
  final totalMinutes = (duration.inSeconds / 60).round();
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '$minutes min';
  if (minutes == 0) return '$hours h';
  return '$hours h ${minutes.toString().padLeft(2, '0')}';
}
