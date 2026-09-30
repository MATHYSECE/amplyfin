import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/movie.dart';
import '../models/movie_details.dart';
import '../models/session.dart';

/// Erreur lisible renvoyée par [JellyfinApi].
class JellyfinException implements Exception {
  JellyfinException(this.message, {this.statusCode});

  final String message;

  /// Code HTTP du serveur (401, 500…), ou null si le serveur n'a pas répondu.
  final int? statusCode;

  /// Vrai si le serveur refuse l'identification (jeton ou mot de passe invalide).
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Nettoie l'adresse saisie : ajoute « http:// » si besoin et retire le « / » final.
/// Lève une [FormatException] si l'adresse est inutilisable.
String normalizeServerUrl(String input) {
  var url = input.trim();
  if (url.isEmpty) throw const FormatException('Adresse vide');
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'http://$url';
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) {
    throw const FormatException('Adresse invalide');
  }
  return url;
}

/// Tous les appels au serveur Jellyfin passent par cette classe.
/// Appels utilisés : voir https://api.jellyfin.org
class JellyfinApi {
  JellyfinApi({required this.serverUrl, required this.deviceId, this.token});

  static const clientName = 'Amplyfin';
  static const clientVersion = '1.0.0';
  static const _timeout = Duration(seconds: 15);

  final String serverUrl;
  final String deviceId;

  /// Jeton de connexion (null tant qu'on n'est pas connecté).
  String? token;

  final http.Client _client = http.Client();

  /// En-tête d'identification attendu par Jellyfin :
  /// MediaBrowser Client="…", Device="…", DeviceId="…", Version="…", Token="…"
  String get _authorizationHeader {
    String quote(String value) => '"${Uri.encodeComponent(value)}"';
    final parts = [
      'Client=${quote(clientName)}',
      'Device=${quote(Platform.isIOS ? 'iPhone' : 'Android')}',
      'DeviceId=${quote(deviceId)}',
      'Version=${quote(clientVersion)}',
      if (token != null) 'Token=${quote(token!)}',
    ];
    return 'MediaBrowser ${parts.join(', ')}';
  }

  // ---------- Appels de l'API ----------

  /// GET /System/Info/Public : vérifie qu'un serveur Jellyfin répond
  /// à cette adresse et renvoie son nom.
  Future<String> getServerName() async {
    final json = await _send('GET', '/System/Info/Public');
    return (json['ServerName'] as String?) ?? 'Jellyfin';
  }

  /// POST /Users/AuthenticateByName : connexion avec identifiant + mot de passe.
  /// Le mot de passe est envoyé une seule fois, puis oublié.
  Future<Session> authenticateByName(String username, String password) async {
    final json = await _send(
      'POST',
      '/Users/AuthenticateByName',
      body: {'Username': username, 'Pw': password},
    );
    final user = json['User'] as Map<String, dynamic>;
    return Session(
      serverUrl: serverUrl,
      accessToken: json['AccessToken'] as String,
      userId: user['Id'] as String,
      userName: (user['Name'] as String?) ?? username,
    );
  }

  /// GET /Users/Me : vérifie que le jeton est toujours valide.
  Future<void> checkToken() => _send('GET', '/Users/Me');

  /// POST /Sessions/Logout : invalide le jeton côté serveur.
  Future<void> logout() => _send('POST', '/Sessions/Logout');

  /// GET /Items : une page de films de l'utilisateur, triés par titre.
  /// [startIndex] = position du premier film voulu, [limit] = taille de la page.
  Future<MoviePage> getMovies({
    required String userId,
    int startIndex = 0,
    int limit = 50,
  }) async {
    final json = await _send(
      'GET',
      '/Items',
      query: {
        'userId': userId,
        'includeItemTypes': 'Movie',
        'recursive': 'true',
        'sortBy': 'SortName',
        'sortOrder': 'Ascending',
        'startIndex': '$startIndex',
        'limit': '$limit',
        // On ne veut que l'affiche, pas les autres images
        'enableImageTypes': 'Primary',
        'imageTypeLimit': '1',
        'enableUserData': 'false',
      },
    );
    final items = (json['Items'] as List<dynamic>?) ?? [];
    return MoviePage(
      movies: [for (final item in items) Movie.fromJson(item)],
      totalCount: (json['TotalRecordCount'] as int?) ?? items.length,
    );
  }

  /// GET /Items/{id}?userId=… : la fiche complète d'un film.
  Future<MovieDetails> getMovieDetails({
    required String userId,
    required String movieId,
  }) async {
    final json = await _send(
      'GET',
      '/Items/$movieId',
      query: {'userId': userId},
    );
    return MovieDetails.fromJson(json as Map<String, dynamic>);
  }

  /// Adresse de l'affiche d'un film, [width] pixels de large.
  /// Null si le film n'a pas d'affiche.
  String? posterUrl(Movie movie, {required int width}) =>
      _imageUrl(movie.id, 'Primary', movie.posterTag, width);

  /// Adresse de l'image de fond d'un film, [width] pixels de large.
  /// Null si le film n'a pas d'image de fond.
  String? backdropUrl(MovieDetails details, {required int width}) =>
      _imageUrl(details.movie.id, 'Backdrop', details.backdropTag, width);

  /// GET /Items/{id}/Images/{type} : image redimensionnée par le serveur.
  /// Cet appel ne demande pas de jeton. Le [tag] (empreinte de l'image)
  /// change quand l'image change, ce qui évite de garder une vieille image
  /// en cache.
  String? _imageUrl(String itemId, String type, String? tag, int width) {
    if (tag == null) return null;
    return Uri.parse('$serverUrl/Items/$itemId/Images/$type')
        .replace(
          queryParameters: {'fillWidth': '$width', 'quality': '90', 'tag': tag},
        )
        .toString();
  }

  // ---------- Envoi des requêtes ----------

  /// Envoie une requête et renvoie le JSON décodé (ou null si réponse vide).
  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$serverUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers['Authorization'] = _authorizationHeader
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw JellyfinException('Le serveur ne répond pas (délai dépassé).');
    } on Exception {
      throw JellyfinException(
        'Impossible de joindre le serveur. Vérifie l\'adresse et ta connexion.',
      );
    }

    if (response.statusCode == 401) {
      throw JellyfinException('Identification refusée.', statusCode: 401);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JellyfinException(
        'Erreur du serveur (code ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw JellyfinException(
        'Réponse illisible : est-ce bien un serveur Jellyfin ?',
      );
    }
  }
}
