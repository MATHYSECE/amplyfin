/// Vitesses proposées dans le lecteur (1 = normale).
const playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// « Normale », « × 1,25 », « × 2 »…
String playbackSpeedLabel(double speed) {
  if (speed == 1) return 'Normale';
  final text = speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString().replaceAll('.', ',');
  return '× $text';
}
