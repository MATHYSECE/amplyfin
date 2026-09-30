import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../models/session.dart';

/// Range la session dans le coffre-fort du téléphone
/// (Keystore sur Android, Keychain sur iPhone) : rien n'est stocké en clair.
class SessionStore {
  static const _storage = FlutterSecureStorage();

  // Noms des cases du coffre-fort
  static const _kServerUrl = 'server_url';
  static const _kToken = 'access_token';
  static const _kUserId = 'user_id';
  static const _kUserName = 'user_name';
  static const _kDeviceId = 'device_id';

  /// Relit la session enregistrée, ou null si personne n'est connecté.
  Future<Session?> load() async {
    final serverUrl = await _storage.read(key: _kServerUrl);
    final token = await _storage.read(key: _kToken);
    final userId = await _storage.read(key: _kUserId);
    final userName = await _storage.read(key: _kUserName);
    if (serverUrl == null || token == null || userId == null) return null;
    return Session(
      serverUrl: serverUrl,
      accessToken: token,
      userId: userId,
      userName: userName ?? '',
    );
  }

  /// Enregistre la session après une connexion réussie.
  Future<void> save(Session session) async {
    await _storage.write(key: _kServerUrl, value: session.serverUrl);
    await _storage.write(key: _kToken, value: session.accessToken);
    await _storage.write(key: _kUserId, value: session.userId);
    await _storage.write(key: _kUserName, value: session.userName);
  }

  /// Oublie la connexion. On garde l'adresse du serveur pour pré-remplir
  /// l'écran de connexion, et l'identifiant de l'appareil.
  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUserId);
    await _storage.delete(key: _kUserName);
  }

  /// Dernière adresse de serveur utilisée (pour pré-remplir le champ).
  Future<String?> lastServerUrl() => _storage.read(key: _kServerUrl);

  /// Identifiant unique de cet appareil, créé une seule fois.
  /// Jellyfin s'en sert pour reconnaître l'appareil dans ses sessions.
  Future<String> deviceId() async {
    var id = await _storage.read(key: _kDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      await _storage.write(key: _kDeviceId, value: id);
    }
    return id;
  }
}
