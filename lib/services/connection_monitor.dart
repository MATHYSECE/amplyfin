import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/jellyfin_api.dart';
import 'offline_progress.dart';

/// Réponse du serveur à une vérification.
enum ServerStatus {
  /// Le serveur répond (même avec une erreur : il est joignable).
  reachable,

  /// Le serveur refuse le jeton (il faut se reconnecter).
  unauthorized,

  /// Pas de réponse : pas de réseau, ou serveur éteint.
  unreachable,
}

/// Vérifie rapidement si le serveur répond (au plus [timeout]).
Future<ServerStatus> checkServer(
  JellyfinApi api, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  try {
    await api.checkToken().timeout(timeout);
    return ServerStatus.reachable;
  } on TimeoutException {
    return ServerStatus.unreachable;
  } on JellyfinException catch (e) {
    if (e.isUnauthorized) return ServerStatus.unauthorized;
    // Pas de code : le serveur n'a pas répondu du tout
    return e.statusCode == null
        ? ServerStatus.unreachable
        : ServerStatus.reachable;
  }
}

/// Sait si le serveur répond. Hors ligne, revérifie toutes les 30 secondes
/// et à chaque retour dans l'appli ; quand le serveur répond de nouveau,
/// les positions de lecture gardées sur le téléphone lui sont envoyées.
class ConnectionMonitor extends ChangeNotifier with WidgetsBindingObserver {
  ConnectionMonitor._();

  static final instance = ConnectionMonitor._();

  static const _retryInterval = Duration(seconds: 30);

  JellyfinApi? _api;
  String? _userId;
  Timer? _timer;
  bool _observing = false;

  bool _online = true;
  bool _checking = false;
  bool _recovered = false;

  /// Vrai si le serveur répondait à la dernière vérification.
  bool get online => _online;

  /// Vrai pendant une vérification (« Réessayer »).
  bool get checking => _checking;

  /// Vrai si on a été hors ligne, puis que le serveur répond de nouveau.
  bool get recovered => _recovered;

  /// Branche le suivi sur la session ouverte, avec le résultat de la
  /// vérification du démarrage.
  void start(JellyfinApi api, String userId, {required bool online}) {
    _api = api;
    _userId = userId;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _recovered = false;
    _setOnline(online);
  }

  /// Vérifie maintenant si le serveur répond.
  Future<bool> check() async {
    final api = _api;
    if (api == null || _checking) return _online;
    _checking = true;
    notifyListeners();
    final status = await checkServer(api);
    _checking = false;
    _setOnline(status != ServerStatus.unreachable);
    return _online;
  }

  void _setOnline(bool online) {
    final wasOffline = !_online;
    _online = online;
    _timer?.cancel();
    if (online) {
      if (wasOffline) _recovered = true;
      // Positions retenues hors ligne : envoyées maintenant
      final api = _api;
      final userId = _userId;
      if (api != null && userId != null) {
        unawaited(OfflineProgress.instance.sync(api, userId));
      }
    } else {
      _timer = Timer.periodic(_retryInterval, (_) => check());
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_online) check();
  }
}
