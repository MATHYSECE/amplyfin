import 'durations.dart';

/// Bande-annonce d'un film ou d'une série : un fichier rangé à côté de la
/// vidéo sur le serveur (téléchargé par Trailarr), lu comme un film.
class Trailer {
  const Trailer({required this.id, this.runtime});

  /// Lu depuis un élément de GET /Items/{id}/LocalTrailers.
  factory Trailer.fromJson(Map<String, dynamic> json) => Trailer(
    id: json['Id'] as String,
    runtime: ticksToDuration((json['RunTimeTicks'] as num?)?.toInt()),
  );

  final String id;

  /// Durée (null si le serveur ne la donne pas).
  final Duration? runtime;

  /// Nom affiché : « Bande-annonce », numérotée s'il y en a plusieurs
  /// ([number] commence à 1), avec sa durée si on la connaît. Le nom du
  /// serveur n'est pas fiable (« Trailer », nom du fichier…).
  String label(int number, int count) {
    final name = count > 1 ? 'Bande-annonce $number' : 'Bande-annonce';
    final length = runtime;
    if (length == null || length == Duration.zero) return name;
    return '$name · ${formatPosition(length)}';
  }
}
