/// Taille des sous-titres, choisie dans le lecteur et retenue sur l'appareil.
enum SubtitleSize {
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

  /// Taille enregistrée → valeur (inconnue ou absente : moyenne).
  static SubtitleSize fromName(String? name) => values.firstWhere(
    (size) => size.name == name,
    orElse: () => SubtitleSize.medium,
  );
}
