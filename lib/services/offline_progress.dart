import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/jellyfin_api.dart';
import '../models/watch_progress.dart';
import 'profile_data.dart';

/// Où en est la lecture d'un fichier téléchargé, gardé sur le téléphone
/// (pour reprendre au bon endroit sans le serveur).
class SavedProgress {
  const SavedProgress({
    required this.position,
    required this.played,
    required this.updatedAt,
    this.runtime,
    this.pending = false,
  });

  /// Position à la fin d'une lecture, avec les mêmes règles que le
  /// serveur : sous 5 % rien n'est retenu, au-delà de 90 % c'est « vu ».
  factory SavedProgress.fromPlayback({
    required Duration position,
    Duration? runtime,
    required DateTime now,
  }) {
    final fraction = (runtime == null || runtime <= Duration.zero)
        ? null
        : position.inMilliseconds / runtime.inMilliseconds;
    if (fraction != null && fraction >= 0.9) {
      return SavedProgress(
        position: Duration.zero,
        played: true,
        updatedAt: now,
        runtime: runtime,
        pending: true,
      );
    }
    return SavedProgress(
      position: (fraction != null && fraction < 0.05)
          ? Duration.zero
          : position,
      played: false,
      updatedAt: now,
      runtime: runtime,
      pending: true,
    );
  }

  /// Ce que le serveur connaît (déjà à jour : rien à envoyer).
  factory SavedProgress.fromServer(
    WatchProgress server, {
    Duration? runtime,
    required DateTime now,
  }) => SavedProgress(
    position: server.position,
    played: server.played,
    updatedAt: server.lastPlayed ?? now,
    runtime: runtime,
  );

  factory SavedProgress.fromJson(Map<String, dynamic> json) => SavedProgress(
    position: Duration(milliseconds: json['position'] as int),
    played: json['played'] == true,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    runtime: json['runtime'] == null
        ? null
        : Duration(milliseconds: json['runtime'] as int),
    pending: json['pending'] == true,
  );

  Map<String, dynamic> toJson() => {
    'position': position.inMilliseconds,
    'played': played,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'runtime': runtime?.inMilliseconds,
    'pending': pending,
  };

  final Duration position;
  final bool played;

  /// Moment de la lecture (pour savoir qui, du téléphone ou du serveur,
  /// a la position la plus récente).
  final DateTime updatedAt;

  /// Durée de la vidéo (pour la barre de progression).
  final Duration? runtime;

  /// Vrai tant que le serveur n'a pas reçu cette position.
  final bool pending;

  /// Où reprendre (le début si déjà vu).
  Duration get resumePosition => played ? Duration.zero : position;

  /// Part déjà vue, de 0 à 1 (0 si la durée est inconnue).
  double get fraction {
    final total = runtime;
    if (total == null || total <= Duration.zero) return 0;
    return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  /// La même chose, comme si elle venait du serveur (pour la fiche).
  WatchProgress toWatchProgress() => WatchProgress(
    position: resumePosition,
    percentage: played ? 100 : fraction * 100,
    played: played,
    lastPlayed: updatedAt,
  );

  SavedProgress sent() => SavedProgress(
    position: position,
    played: played,
    updatedAt: updatedAt,
    runtime: runtime,
  );
}

/// Vrai si la position du téléphone est au moins aussi récente que celle du
/// serveur (dernière lecture [serverLastPlayed], sur n'importe quel
/// appareil) : c'est alors elle qui compte.
bool phoneIsNewer(SavedProgress phone, DateTime? serverLastPlayed) =>
    serverLastPlayed == null || !serverLastPlayed.isAfter(phone.updatedAt);

/// Positions de lecture des fichiers téléchargés, gardées sur le téléphone,
/// et envoyées au serveur dès qu'il répond (la plus récente gagne).
class OfflineProgress extends ChangeNotifier {
  OfflineProgress._();

  static final instance = OfflineProgress._();

  static const _name = 'offline_progress';

  final Map<String, SavedProgress> _items = {};
  Future<void>? _ready;
  Future<void>? _syncing;

  /// Profil dont les positions sont chargées (chacun a les siennes).
  String? _loadedFor;

  /// Relit les positions du profil en cours (au démarrage, et à chaque
  /// changement de profil).
  Future<void> init() {
    final userId = ProfileData.userId;
    if (_ready == null || userId != _loadedFor) {
      _loadedFor = userId;
      _items.clear();
      notifyListeners();
      _ready = _load(userId);
    }
    return _ready!;
  }

  Future<void> _load(String? userId) async {
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(ProfileData.key(_name, userId: userId));
    if (text == null || userId != _loadedFor) return;
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      for (final MapEntry(key: id, value: value) in json.entries) {
        _items[id] = SavedProgress.fromJson(value as Map<String, dynamic>);
      }
    } on Object {
      // Données abîmées : on repart de zéro
      _items.clear();
    }
    notifyListeners();
  }

  /// Position gardée pour cet élément (null si jamais lu depuis le
  /// téléphone).
  SavedProgress? of(String itemId) => _items[itemId];

  /// Retient la position d'une lecture du fichier téléchargé.
  Future<void> record(
    String itemId, {
    required Duration position,
    Duration? runtime,
  }) async {
    await init();
    _items[itemId] = SavedProgress.fromPlayback(
      position: position,
      runtime: runtime,
      now: DateTime.now(),
    );
    notifyListeners();
    await _save();
  }

  /// Retient ce que le serveur sait déjà (pour reprendre hors ligne).
  Future<void> remember(
    String itemId,
    WatchProgress server, {
    Duration? runtime,
  }) async {
    await init();
    _items[itemId] = SavedProgress.fromServer(
      server,
      runtime: runtime,
      now: DateTime.now(),
    );
    notifyListeners();
    await _save();
  }

  /// Envoie au serveur les positions en attente. Pour chacune, la plus
  /// récente (téléphone ou serveur) gagne. S'arrête au premier problème de
  /// connexion (on réessaiera plus tard).
  Future<void> sync(JellyfinApi api, String userId) =>
      _syncing ??= _sync(api, userId).whenComplete(() => _syncing = null);

  Future<void> _sync(JellyfinApi api, String userId) async {
    await init();
    // Jamais les positions d'une personne sur le compte d'une autre
    if (userId != _loadedFor) return;
    final pending = [
      for (final MapEntry(key: id, value: saved) in _items.entries)
        if (saved.pending) (id, saved),
    ];
    var changed = false;
    for (final (id, saved) in pending) {
      try {
        final server =
            (await api
                    .getItemDetails(userId: userId, itemId: id)
                    .timeout(const Duration(seconds: 8)))
                .progress;
        if (phoneIsNewer(saved, server.lastPlayed)) {
          await api.updateWatchProgress(
            userId: userId,
            itemId: id,
            position: saved.resumePosition,
            played: saved.played,
            lastPlayed: saved.updatedAt,
          );
          _items[id] = saved.sent();
        } else {
          // Regardé plus récemment ailleurs : on prend la position du serveur
          _items[id] = SavedProgress.fromServer(
            server,
            runtime: saved.runtime,
            now: DateTime.now(),
          );
        }
        changed = true;
      } on JellyfinException catch (e) {
        // Supprimé du serveur : plus rien à envoyer
        if (e.statusCode == 404) {
          _items[id] = saved.sent();
          changed = true;
          continue;
        }
        break;
      } on TimeoutException {
        break;
      }
    }
    if (changed) {
      notifyListeners();
      await _save();
    }
  }

  Future<void> _save() async {
    final userId = _loadedFor;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      ProfileData.key(_name, userId: userId),
      jsonEncode({
        for (final MapEntry(key: id, value: saved) in _items.entries)
          id: saved.toJson(),
      }),
    );
  }
}
