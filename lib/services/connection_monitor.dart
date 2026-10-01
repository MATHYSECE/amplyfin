import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
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

/// Vrai si le téléphone n'a plus aucun réseau (mode avion, Wi-Fi et
/// données coupés).
bool hasNoNetwork(List<ConnectivityResult> results) =>
    results.isEmpty || results.every((r) => r == ConnectivityResult.none);

/// Sait si le serveur répond, et le dit tout de suite :
/// - le téléphone prévient quand le réseau se coupe ou revient (le retour
///   est confirmé auprès du serveur, en réessayant un peu plus tard si
///   besoin) ;
/// - une demande au serveur sans réponse déclenche une vérification ;
/// - hors ligne, nouvel essai toutes les 30 secondes et au retour dans
///   l'appli.
/// Au retour du serveur, les positions de lecture gardées sur le téléphone
/// lui sont envoyées.
class ConnectionMonitor extends ChangeNotifier with WidgetsBindingObserver {
  ConnectionMonitor._();

  static final instance = ConnectionMonitor._();

  static const _retryInterval = Duration(seconds: 30);

  /// Vérifications au retour du réseau : le serveur met souvent une ou deux
  /// secondes à redevenir joignable.
  static const _reconnectDelays = [
    Duration.zero,
    Duration(milliseconds: 1500),
    Duration(seconds: 4),
  ];

  /// Durée de l'indication « De nouveau en ligne ».
  static const _reconnectedFor = Duration(seconds: 3);

  JellyfinApi? _api;
  String? _userId;
  Timer? _timer;
  Timer? _reconnectedTimer;
  StreamSubscription<List<ConnectivityResult>>? _network;
  bool _observing = false;

  bool _online = true;
  bool _checking = false;
  bool _recovered = false;
  bool _justReconnected = false;

  /// Vrai si le serveur répondait à la dernière vérification.
  bool get online => _online;

  /// Vrai pendant une vérification.
  bool get checking => _checking;

  /// Vrai si on a été hors ligne, puis que le serveur répond de nouveau.
  bool get recovered => _recovered;

  /// Vrai pendant quelques secondes après le retour de la connexion.
  bool get justReconnected => _justReconnected;

  /// Branche le suivi sur la session ouverte, avec le résultat de la
  /// vérification du démarrage.
  void start(JellyfinApi api, String userId, {required bool online}) {
    _api = api;
    _userId = userId;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _network ??= Connectivity().onConnectivityChanged.listen(_onNetwork);
    JellyfinApi.onServerUnreachable = _onRequestFailed;
    JellyfinApi.onServerReached = _onRequestAnswered;
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

  /// Le réseau du téléphone change.
  void _onNetwork(List<ConnectivityResult> results) {
    if (hasNoNetwork(results)) {
      // Plus de réseau : hors ligne tout de suite
      _setOnline(false);
    } else {
      // Réseau revenu (ou changé) : le serveur répond-il ?
      _checkSoon();
    }
  }

  /// Vérifie tout de suite, puis un peu plus tard si le serveur ne répond
  /// pas encore.
  Future<void> _checkSoon() async {
    for (final delay in _reconnectDelays) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (await check()) return;
    }
  }

  /// Une demande n'a obtenu aucune réponse : on vérifie.
  void _onRequestFailed() {
    if (_online && !_checking) check();
  }

  /// Une demande a obtenu une réponse : le serveur est là.
  void _onRequestAnswered() {
    if (!_online) _setOnline(true);
  }

  void _setOnline(bool online) {
    final wasOffline = !_online;
    _online = online;
    _timer?.cancel();
    if (online) {
      if (wasOffline) {
        _recovered = true;
        _justReconnected = true;
        _reconnectedTimer?.cancel();
        _reconnectedTimer = Timer(_reconnectedFor, () {
          _justReconnected = false;
          notifyListeners();
        });
        // Positions retenues hors ligne : envoyées maintenant
        final api = _api;
        final userId = _userId;
        if (api != null && userId != null) {
          unawaited(OfflineProgress.instance.sync(api, userId));
        }
      }
    } else {
      _justReconnected = false;
      _timer = Timer.periodic(_retryInterval, (_) => check());
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_online) check();
  }
}
