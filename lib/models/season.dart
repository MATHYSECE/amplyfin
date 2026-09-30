/// Une saison d'une série (GET /Shows/{id}/Seasons).
class Season {
  const Season({required this.id, required this.name, this.number});

  factory Season.fromJson(Map<String, dynamic> json) {
    final number = json['IndexNumber'] as int?;
    return Season(
      id: json['Id'] as String,
      // Le serveur donne déjà un nom (« Saison 1 », « Spéciaux »…)
      name:
          (json['Name'] as String?) ??
          (number == null ? 'Saison' : 'Saison $number'),
      number: number,
    );
  }

  final String id;
  final String name;

  /// Numéro de la saison (0 pour les épisodes spéciaux).
  final int? number;
}
