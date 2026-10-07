/// Taille des sous-titres, choisie dans le lecteur et retenue sur l'appareil.
enum SubtitleSize {
  extraSmall('Très petite', 0.031),
  small('Petite', 0.038),
  medium('Moyenne', 0.047),
  large('Grande', 0.058);

  const SubtitleSize(this.label, this.heightFactor);

  /// Nom affiché dans le menu.
  final String label;

  /// Taille du texte, en part de la hauteur de l'image : les sous-titres
  /// gardent les mêmes proportions sur un téléphone et sur une tablette.
  final double heightFactor;

  /// Taille du texte pour une image haute de [height].
  double fontSizeFor(double height) => height * heightFactor;

  /// Taille par défaut (la plus utilisée).
  static const standard = SubtitleSize.small;

  /// Taille enregistrée → valeur (inconnue ou absente : [standard]).
  static SubtitleSize fromName(String? name) =>
      values.firstWhere((size) => size.name == name, orElse: () => standard);
}
