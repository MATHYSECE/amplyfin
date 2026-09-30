import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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
