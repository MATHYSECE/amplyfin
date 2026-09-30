/// Noms des langues, à partir des codes donnés par le serveur (ISO 639-2,
/// ex. « fre », « eng »).
library;

/// Certaines langues ont deux codes : on garde toujours le même.
const _synonyms = {
  'fra': 'fre',
  'deu': 'ger',
  'nld': 'dut',
  'zho': 'chi',
  'ces': 'cze',
  'ell': 'gre',
  'fas': 'per',
  'ron': 'rum',
  'slk': 'slo',
};

const _names = {
  'fre': 'Français',
  'eng': 'Anglais',
  'spa': 'Espagnol',
  'ger': 'Allemand',
  'ita': 'Italien',
  'por': 'Portugais',
  'dut': 'Néerlandais',
  'jpn': 'Japonais',
  'kor': 'Coréen',
  'chi': 'Chinois',
  'rus': 'Russe',
  'ara': 'Arabe',
  'hin': 'Hindi',
  'tur': 'Turc',
  'pol': 'Polonais',
  'swe': 'Suédois',
  'nor': 'Norvégien',
  'dan': 'Danois',
  'fin': 'Finnois',
  'cze': 'Tchèque',
  'gre': 'Grec',
  'heb': 'Hébreu',
  'hun': 'Hongrois',
  'rum': 'Roumain',
  'ukr': 'Ukrainien',
  'tha': 'Thaï',
  'vie': 'Vietnamien',
};

/// Code de langue unifié (minuscules, un seul code par langue),
/// ou null si inconnu.
String? normalizeLanguage(String? code) {
  if (code == null || code.isEmpty) return null;
  final lower = code.toLowerCase();
  if (lower == 'und') return null; // « indéterminée »
  return _synonyms[lower] ?? lower;
}

/// Nom de la langue en français : « Français », « Anglais »…
String languageName(String? code) {
  final normalized = normalizeLanguage(code);
  if (normalized == null) return 'Langue inconnue';
  return _names[normalized] ?? normalized.toUpperCase();
}
