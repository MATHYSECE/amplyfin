/// Petits outils pour les durées.
library;

/// Jellyfin compte les durées en « ticks » : 10 millions par seconde.
Duration? ticksToDuration(int? ticks) =>
    ticks == null ? null : Duration(microseconds: ticks ~/ 10);

/// L'inverse : une durée en « ticks » (pour les signalements au serveur).
int durationToTicks(Duration duration) => duration.inMicroseconds * 10;

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
