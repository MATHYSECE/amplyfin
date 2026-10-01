import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/durations.dart';
import '../models/episode.dart';
import '../models/item_details.dart';
import '../models/media_item.dart';
import '../models/playback_info.dart';
import '../models/playback_quality.dart';
import '../models/resume_entry.dart';
import '../models/season.dart';
import '../models/session.dart';
import '../models/track_choice.dart';
import 'device_profile.dart';

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

  /// GET /Items : une page de films ou de séries de l'utilisateur, triés
  /// par titre. [type] : « Movie » ou « Series ».
  /// [startIndex] = position du premier élément voulu, [limit] = taille de la page.
  Future<ItemPage> getItems({
    required String userId,
    required String type,
    int startIndex = 0,
    int limit = 50,
  }) async {
    final json = await _send(
      'GET',
      '/Items',
      query: {
        'userId': userId,
        'includeItemTypes': type,
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
    return ItemPage(
      items: [for (final item in items) MediaItem.fromJson(item)],
      totalCount: (json['TotalRecordCount'] as int?) ?? items.length,
    );
  }

  /// GET /Items/{id}?userId=… : la fiche complète d'un film ou d'une série.
  Future<ItemDetails> getItemDetails({
    required String userId,
    required String itemId,
  }) async {
    final json = await _send(
      'GET',
      '/Items/$itemId',
      query: {'userId': userId},
    );
    return ItemDetails.fromJson(json as Map<String, dynamic>);
  }

  /// GET /Items/{id}?userId=… : la fiche complète, telle quelle (gardée avec
  /// un téléchargement pour l'afficher et le lire sans le serveur).
  Future<Map<String, dynamic>> getItemJson({
    required String userId,
    required String itemId,
  }) async {
    final json = await _send(
      'GET',
      '/Items/$itemId',
      query: {'userId': userId},
    );
    return json as Map<String, dynamic>;
  }

  /// GET /Items/{id}/Download : le fichier d'origine, pour le télécharger
  /// (le compte doit avoir le droit de télécharger sur le serveur).
  String downloadUrl(String itemId) => '$serverUrl/Items/$itemId/Download';

  /// Sous-titres séparés d'un fichier, convertis au format SRT
  /// (GET /Videos/{id}/{source}/Subtitles/{numéro}/Stream.srt).
  String subtitleFileUrl({
    required String itemId,
    required String mediaSourceId,
    required int index,
  }) => '$serverUrl/Videos/$itemId/$mediaSourceId/Subtitles/$index/Stream.srt';

  /// GET /Shows/{id}/Seasons : les saisons d'une série.
  Future<List<Season>> getSeasons({
    required String userId,
    required String seriesId,
  }) async {
    final json = await _send(
      'GET',
      '/Shows/$seriesId/Seasons',
      query: {'userId': userId, 'enableImages': 'false'},
    );
    final items = (json['Items'] as List<dynamic>?) ?? [];
    return [for (final item in items) Season.fromJson(item)];
  }

  /// GET /Shows/{id}/Episodes : les épisodes d'une saison.
  Future<List<Episode>> getEpisodes({
    required String userId,
    required String seriesId,
    required String seasonId,
  }) async {
    final json = await _send(
      'GET',
      '/Shows/$seriesId/Episodes',
      query: {
        'userId': userId,
        'seasonId': seasonId,
        // Résumé, pistes (pour la qualité) et fichiers (pour la taille) ne
        // sont pas envoyés par défaut
        'fields': 'Overview,MediaStreams,MediaSources',
        'enableImageTypes': 'Primary',
        'imageTypeLimit': '1',
        // Pour savoir si l'épisode a déjà été vu
        'enableUserData': 'true',
      },
    );
    final items = (json['Items'] as List<dynamic>?) ?? [];
    return [for (final item in items) Episode.fromJson(item)];
  }

  /// GET /UserItems/Resume : films et épisodes commencés, du plus récent
  /// au plus ancien (rangée « Continuer à regarder »).
  Future<List<ResumeEntry>> getResumeItems({
    required String userId,
    int limit = 20,
  }) async {
    final json = await _send(
      'GET',
      '/UserItems/Resume',
      query: {
        'userId': userId,
        'limit': '$limit',
        'includeItemTypes': 'Movie,Episode',
        'mediaTypes': 'Video',
        // Pistes : pour appliquer les langues choisies pour la série
        'fields': 'MediaStreams',
        'enableUserData': 'true',
        'enableImageTypes': 'Primary',
        'imageTypeLimit': '1',
        'enableTotalRecordCount': 'false',
      },
    );
    final items = (json['Items'] as List<dynamic>?) ?? [];
    return [for (final item in items) ResumeEntry.fromJson(item)];
  }

  /// POST /UserItems/{id}/UserData : change où en est la lecture d'un film
  /// ou d'un épisode. Position 0 et [played] faux : comme jamais regardé
  /// (il sort aussi de « Continuer à regarder »).
  Future<void> updateWatchProgress({
    required String userId,
    required String itemId,
    required Duration position,
    required bool played,
  }) => _send(
    'POST',
    '/UserItems/$itemId/UserData',
    query: {'userId': userId},
    body: {
      'PlaybackPositionTicks': durationToTicks(position),
      'Played': played,
    },
  );

  /// Adresse de l'affiche d'un film ou d'une série, [width] pixels de large.
  /// Null s'il n'y a pas d'affiche.
  String? posterUrl(MediaItem item, {required int width}) =>
      _imageUrl(item.id, 'Primary', item.posterTag, width);

  /// Adresse de l'image de fond, [width] pixels de large.
  /// Null s'il n'y a pas d'image de fond.
  String? backdropUrl(ItemDetails details, {required int width}) =>
      _imageUrl(details.item.id, 'Backdrop', details.backdropTag, width);

  /// Adresse de la vignette d'un épisode, [width] pixels de large.
  /// Null si l'épisode n'a pas de vignette.
  String? episodeImageUrl(Episode episode, {required int width}) =>
      _imageUrl(episode.id, 'Primary', episode.imageTag, width);

  /// Adresse d'une image quelconque d'un élément ([type] : « Primary »,
  /// « Backdrop »…), [width] pixels de large. Null si [tag] est null.
  String? imageUrl({
    required String itemId,
    required String type,
    required String? tag,
    required int width,
  }) => _imageUrl(itemId, type, tag, width);

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

  // ---------- Lecture vidéo ----------

  /// POST /Items/{id}/PlaybackInfo : demande au serveur comment lire un film.
  /// Qualité originale : lecture directe si possible.
  /// Qualité réduite : flux converti par le serveur (débit et largeur limités).
  /// [start] : position de départ, pour que le serveur commence sa conversion
  /// directement au bon endroit (sinon il part du début et le lecteur attend).
  /// [supports10Bit] : faux si l'appareil ne décode pas les vidéos 10 bits.
  /// [tracks] : pistes audio et sous-titres voulues (le serveur les renvoie
  /// ensuite comme choix par défaut, et les met dans le flux s'il convertit).
  /// [allowDirectPlay] : faux pour forcer une vraie conversion (quand
  /// l'appareil n'a pas réussi à décoder l'image du fichier).
  Future<PlaybackInfo> getPlaybackInfo({
    required String userId,
    required String itemId,
    required PlaybackQuality quality,
    Duration start = Duration.zero,
    bool supports10Bit = true,
    TrackSelection tracks = const TrackSelection(),
    bool allowDirectPlay = true,
  }) async {
    final bitrate = quality.maxBitrate ?? originalMaxBitrate;
    final json = await _send(
      'POST',
      '/Items/$itemId/PlaybackInfo',
      query: {'userId': userId},
      body: {
        'UserId': userId,
        'StartTimeTicks': durationToTicks(start),
        if (tracks.audioIndex != null) 'AudioStreamIndex': tracks.audioIndex,
        if (tracks.subtitleIndex != null)
          'SubtitleStreamIndex': tracks.subtitleIndex,
        'MaxStreamingBitrate': bitrate,
        'DeviceProfile': buildDeviceProfile(
          maxBitrate: bitrate,
          maxWidth: quality.maxWidth,
          maxBitDepth: supports10Bit ? null : 8,
        ),
        'EnableDirectPlay': quality.isOriginal && allowDirectPlay,
        'EnableDirectStream': quality.isOriginal && allowDirectPlay,
        'EnableTranscoding': true,
        // Si une conversion a lieu, le serveur recopie tel quel ce qu'il peut
        // (sauf conversion forcée : recopier l'image illisible ne servirait à rien)
        'AllowVideoStreamCopy': allowDirectPlay,
        'AllowAudioStreamCopy': true,
        'AutoOpenLiveStream': true,
      },
    );
    try {
      return PlaybackInfo.fromJson(
        json as Map<String, dynamic>,
        itemId: itemId,
      );
    } on FormatException catch (e) {
      throw JellyfinException(e.message);
    }
  }

  /// Adresse complète de la vidéo à donner au lecteur :
  /// - lecture directe : GET /Videos/{id}/stream?static=true (fichier original) ;
  /// - sinon : le flux HLS converti (TranscodingUrl, adresse partielle).
  String streamUrl(PlaybackInfo info) {
    if (info.directPlay) {
      return Uri.parse('$serverUrl/Videos/${info.itemId}/stream')
          .replace(
            queryParameters: {
              'static': 'true',
              'mediaSourceId': info.mediaSourceId,
              'playSessionId': info.playSessionId,
              'deviceId': deviceId,
            },
          )
          .toString();
    }
    final url = info.transcodingUrl!;
    return url.startsWith('http') ? url : '$serverUrl$url';
  }

  /// Adresse complète à partir d'une adresse partielle du serveur
  /// (ex. l'adresse d'un fichier de sous-titres).
  /// Les fichiers du téléphone (« file:// ») sont gardés tels quels.
  String absoluteUrl(String url) =>
      url.startsWith('http') || url.startsWith('file:')
      ? url
      : '$serverUrl$url';

  /// En-têtes à joindre aux requêtes du lecteur vidéo (identification).
  Map<String, String> get streamHeaders => {
    'Authorization': _authorizationHeader,
  };

  /// POST /Sessions/Playing : la lecture commence.
  Future<void> reportPlaybackStart(PlaybackInfo info, Duration position) =>
      _send('POST', '/Sessions/Playing', body: _playbackReport(info, position));

  /// POST /Sessions/Playing/Progress : où en est la lecture.
  Future<void> reportPlaybackProgress(
    PlaybackInfo info,
    Duration position, {
    required bool isPaused,
  }) => _send(
    'POST',
    '/Sessions/Playing/Progress',
    body: {..._playbackReport(info, position), 'IsPaused': isPaused},
  );

  /// POST /Sessions/Playing/Stopped : la lecture s'arrête. Le serveur coupe
  /// alors une éventuelle conversion et retient la position.
  Future<void> reportPlaybackStopped(PlaybackInfo info, Duration position) =>
      _send(
        'POST',
        '/Sessions/Playing/Stopped',
        body: {
          'ItemId': info.itemId,
          'MediaSourceId': info.mediaSourceId,
          'PlaySessionId': info.playSessionId,
          'PositionTicks': durationToTicks(position),
        },
      );

  /// Contenu commun des signalements de début et de progression.
  Map<String, dynamic> _playbackReport(PlaybackInfo info, Duration position) =>
      {
        'ItemId': info.itemId,
        'MediaSourceId': info.mediaSourceId,
        'PlaySessionId': info.playSessionId,
        'PositionTicks': durationToTicks(position),
        'PlayMethod': info.playMethod,
        'CanSeek': true,
      };

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
