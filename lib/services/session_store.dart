import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../models/session.dart';
import 'profile_data.dart';

/// Range les profils dans le coffre-fort du téléphone
/// (Keystore sur Android, Keychain sur iPhone) : rien n'est stocké en clair.
/// Un profil = une personne connectée sur l'appareil, avec son jeton (jamais
/// son mot de passe). Tous partagent l'identifiant de l'appareil : Jellyfin
/// ne coupe que les anciennes connexions de la même personne.
class SessionStore {
  static const _storage = FlutterSecureStorage();

  // Noms des cases du coffre-fort
  static const _kProfiles = 'profiles';
  static const _kCurrent = 'current_profile';
  static const _kServerUrl = 'server_url';
  static const _kDeviceId = 'device_id';

  // Cases d'avant les profils (un seul compte), reprises au premier lancement
  static const _kOldToken = 'access_token';
  static const _kOldUserId = 'user_id';
  static const _kOldUserName = 'user_name';

  /// Tous les profils de l'appareil, dans l'ordre d'ajout.
  Future<List<Session>> profiles() async {
    final text = await _storage.read(key: _kProfiles);
    if (text == null) return _adoptOldSession();
    try {
      return [
        for (final json in jsonDecode(text) as List)
          Session.fromJson(json as Map<String, dynamic>),
      ];
    } on Object {
      // Données abîmées : personne n'est connecté
      return [];
    }
  }

  /// Profil en cours, ou null si personne n'est connecté.
  Future<Session?> load() async {
    final all = await profiles();
    final current = await _storage.read(key: _kCurrent);
    final session = all.where((s) => s.userId == current).firstOrNull;
    ProfileData.use(session?.userId);
    return session;
  }

  /// Enregistre la session après une connexion réussie : nouveau profil,
  /// ou jeton mis à jour pour un compte déjà présent. Il devient le profil
  /// en cours.
  Future<void> save(Session session) async {
    final all = await profiles();
    // Compte déjà présent : même place, nouveau jeton
    final index = all.indexWhere((s) => s.sameAccount(session));
    if (index < 0) {
      all.add(session);
    } else {
      all[index] = session;
    }
    await _write(all);
    await _storage.write(key: _kServerUrl, value: session.serverUrl);
    await _storage.write(key: _kCurrent, value: session.userId);
    ProfileData.use(session.userId);
  }

  /// Retire le profil en cours (déconnexion). Les autres profils restent ;
  /// l'adresse du serveur et l'identifiant de l'appareil aussi.
  Future<void> clear() async {
    final current = await _storage.read(key: _kCurrent);
    await _write([
      for (final session in await profiles())
        if (session.userId != current) session,
    ]);
    await _storage.delete(key: _kCurrent);
    ProfileData.use(null);
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

  Future<void> _write(List<Session> all) => _storage.write(
    key: _kProfiles,
    value: jsonEncode([for (final session in all) session.toJson()]),
  );

  /// Premier lancement avec les profils : la connexion d'avant devient le
  /// premier profil (sans se reconnecter), avec ses données sur l'appareil.
  Future<List<Session>> _adoptOldSession() async {
    final serverUrl = await _storage.read(key: _kServerUrl);
    final token = await _storage.read(key: _kOldToken);
    final userId = await _storage.read(key: _kOldUserId);
    final userName = await _storage.read(key: _kOldUserName);
    final all = [
      if (serverUrl != null && token != null && userId != null)
        Session(
          serverUrl: serverUrl,
          accessToken: token,
          userId: userId,
          userName: userName ?? '',
        ),
    ];
    await _write(all);
    if (all.isNotEmpty) {
      await _storage.write(key: _kCurrent, value: all.first.userId);
      await ProfileData.adoptLegacy(all.first.userId);
    }
    for (final old in [_kOldToken, _kOldUserId, _kOldUserName]) {
      await _storage.delete(key: old);
    }
    return all;
  }
}
