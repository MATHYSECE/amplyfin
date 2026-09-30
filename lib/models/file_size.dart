/// Taille de fichier lisible, à la française : « 12,4 Go », « 850 Mo ».
/// Null si la taille est inconnue.
String? formatFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return null;
  const kilo = 1000;
  const units = ['o', 'Ko', 'Mo', 'Go', 'To'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= kilo && unit < units.length - 1) {
    value /= kilo;
    unit++;
  }
  // Une décimale sous 100 (« 12,4 Go »), aucune au-delà (« 850 Mo »)
  final text = value < 100 && unit > 0
      ? value.toStringAsFixed(1)
      : value.toStringAsFixed(0);
  return '${text.replaceAll('.', ',')} ${units[unit]}';
}
