import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/jellyfin_api.dart';
import '../models/download_info.dart';
import '../models/playback_info.dart';

/// Où en est le téléchargement d'un film ou d'un épisode.
enum DownloadPhase { none, waiting, running, paused, complete, failed }

/// État du téléchargement d'un élément, tel qu'affiché par les écrans.
class DownloadState {
  const DownloadState({
    this.phase = DownloadPhase.none,
    this.progress = 0,
    this.expectedSize,
    this.info,
    this.error,
    this.createdAt,
  });

  final DownloadPhase phase;

  /// Part téléchargée, de 0 à 1.
  final double progress;

  /// Taille totale attendue, en octets (si connue).
  final int? expectedSize;

  /// Infos gardées avec le téléchargement (titre, pistes…).
  final DownloadInfo? info;

  /// Message à afficher si le téléchargement a échoué.
  final String? error;

  /// Moment où le téléchargement a été demandé (pour l'ordre des listes).
  final DateTime? createdAt;

  bool get isActive =>
      phase == DownloadPhase.waiting ||
      phase == DownloadPhase.running ||
      phase == DownloadPhase.paused;

  /// Taille du fichier : celle annoncée au téléchargement, sinon celle du
  /// serveur.
  int? get size =>
      (expectedSize != null && expectedSize! > 0) ? expectedSize : info?.size;

  /// Octets déjà reçus (si la taille est connue).
  int? get receivedBytes => size == null ? null : (size! * progress).round();

  DownloadState copyWith({
    DownloadPhase? phase,
    double? progress,
    int? expectedSize,
    DownloadInfo? info,
    String? error,
  }) => DownloadState(
    phase: phase ?? this.phase,
    progress: progress ?? this.progress,
    expectedSize: expectedSize ?? this.expectedSize,
    info: info ?? this.info,
    error: error,
    createdAt: createdAt,
  );
}

/// Télécharge les films et épisodes (fichier d'origine) avec
/// background_downloader : le téléchargement continue quand l'appli est en
/// arrière-plan, reprend après une coupure, et attend le Wi-Fi.
/// Un seul gestionnaire pour toute l'appli ; les écrans l'écoutent pour
/// afficher la progression.
class DownloadManager extends ChangeNotifier {
  DownloadManager._();

  static final instance = DownloadManager._();

  /// Groupe des vidéos, et groupe des petits fichiers qui les accompagnent
  /// (affiche, fond, vignette, sous-titres séparés).
  static const _mediaGroup = 'media';
  static const _extrasGroup = 'extras';

  /// Vidéos téléchargées en même temps : les autres attendent leur tour
  /// (une saison entière ne se partage pas le Wi-Fi en 22 morceaux).
  static const _maxParallel = 2;

  /// Dossier des téléchargements (non sauvegardé dans iCloud).
  static const _directory = 'downloads';
  static const _baseDirectory = BaseDirectory.applicationSupport;

  final Map<String, DownloadState> _states = {};
  Future<void>? _ready;

  /// Chemin complet du dossier des téléchargements (connu après [init]).
  String? _directoryPath;

  /// État du téléchargement de cet élément (rien si jamais téléchargé).
  DownloadState stateOf(String itemId) =>
      _states[itemId] ?? const DownloadState();

  /// Tous les téléchargements connus (identifiant → état).
  Map<String, DownloadState> get states => UnmodifiableMapView(_states);

  /// Nombre de téléchargements pas encore terminés.
  int get activeCount => _states.values.where((s) => s.isActive).length;

  /// Avancée de l'ensemble des téléchargements en cours, de 0 à 1
  /// (null s'il n'y en a pas, ou si les tailles sont inconnues).
  double? get activeProgress {
    var total = 0;
    var received = 0;
    for (final state in _states.values.where((s) => s.isActive)) {
      total += state.size ?? 0;
      received += state.receivedBytes ?? 0;
    }
    return total == 0 ? null : received / total;
  }

  /// Place prise sur le téléphone par les vidéos (terminées, et la partie
  /// déjà reçue de celles en cours), en octets.
  int get usedBytes => _states.values.fold(
    0,
    (sum, s) =>
        sum +
        (s.phase == DownloadPhase.complete
            ? (s.size ?? 0)
            : (s.isActive ? (s.receivedBytes ?? 0) : 0)),
  );

  /// Prépare le téléchargeur au démarrage de l'appli : réglages,
  /// notifications, et reprise des téléchargements déjà connus.
  Future<void> init() => _ready ??= _init();

  Future<void> _init() async {
    final downloader = FileDownloader();
    await downloader.configure(
      globalConfig: [
        // Pas de vidéos de plusieurs Go dans la sauvegarde iCloud
        (Config.excludeFromCloudBackup, Config.always),
        // iPhone : temps laissé pour finir un gros fichier (4 h par défaut)
        (Config.resourceTimeout, const Duration(hours: 48)),
        // Deux vidéos à la fois au plus (par groupe)
        (Config.holdingQueue, (null, null, _maxParallel)),
        // iPhone : boutons des notifications en français (Android : fichier
        // android/app/src/main/res/values/strings.xml)
        (
          Config.localize,
          {'Cancel': 'Annuler', 'Pause': 'Pause', 'Resume': 'Reprendre'},
        ),
      ],
      // Android : service de premier plan (notification) pour les longs
      // téléchargements, sinon Android les coupe au bout de 9 minutes
      androidConfig: [(Config.runInForeground, Config.always)],
    );
    downloader.configureNotificationForGroup(
      _mediaGroup,
      running: const TaskNotification('Téléchargement', '{displayName}'),
      complete: const TaskNotification(
        'Téléchargement terminé',
        '{displayName}',
      ),
      error: const TaskNotification('Téléchargement échoué', '{displayName}'),
      paused: const TaskNotification(
        'Téléchargement en pause',
        '{displayName}',
      ),
      progressBar: true,
    );
    // Appui sur une notification : l'écran qui écoute ouvre les
    // téléchargements
    downloader.registerCallbacks(
      group: _mediaGroup,
      taskNotificationTapCallback: (_, _) => onNotificationTap?.call(),
    );
    downloader.updates.listen(_onUpdate);
    await downloader.start();
    // Données mobiles autorisées ou non (réglage retenu sur le téléphone)
    final prefs = await SharedPreferences.getInstance();
    _mobileData = prefs.getBool(_mobileDataKey) ?? false;
    await _applyNetworkRule();
    _directoryPath = File(await _filePath('_')).parent.path;

    // Téléchargements déjà connus (terminés, ou en cours avant la fermeture)
    for (final record in await downloader.database.allRecords(
      group: _mediaGroup,
    )) {
      _states[record.taskId] = DownloadState(
        phase: _phaseOf(record.status),
        progress: record.status == TaskStatus.complete
            ? 1
            : record.progress.clamp(0.0, 1.0),
        expectedSize: record.expectedFileSize,
        info: _infoOf(record.task),
        error: _errorOf(record.status, record.exception),
        createdAt: record.task.creationTime,
      );
    }
    notifyListeners();
  }

  /// Appelé quand on touche la notification d'un téléchargement (l'écran
  /// principal ouvre alors l'écran Téléchargements).
  VoidCallback? onNotificationTap;

  static const _mobileDataKey = 'downloads_mobile_data';
  bool _mobileData = false;

  /// Vrai si les téléchargements peuvent aussi passer par les données
  /// mobiles (sinon : Wi-Fi uniquement, le réglage par défaut).
  bool get allowsMobileData => _mobileData;

  /// Change le réglage « données mobiles » : s'applique aussi aux
  /// téléchargements déjà lancés.
  Future<void> setMobileData(bool allowed) async {
    await init();
    _mobileData = allowed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mobileDataKey, allowed);
    await _applyNetworkRule();
    notifyListeners();
  }

  Future<void> _applyNetworkRule() => FileDownloader().requireWiFi(
    _mobileData ? RequireWiFi.forNoTasks : RequireWiFi.forAllTasks,
  );

  /// Lance le téléchargement d'un film ou d'un épisode (Wi-Fi uniquement,
  /// sauf si les données mobiles sont autorisées).
  Future<void> start({
    required JellyfinApi api,
    required String userId,
    required String itemId,
  }) => startAll(api: api, userId: userId, itemIds: [itemId]);

  /// Lance le téléchargement de plusieurs éléments (ex. une saison) :
  /// tous passent tout de suite « en attente », puis sont mis en file un
  /// par un. Ceux déjà téléchargés ou en cours sont laissés tels quels.
  Future<void> startAll({
    required JellyfinApi api,
    required String userId,
    required List<String> itemIds,
  }) async {
    await init();
    final todo = [
      for (final id in itemIds)
        if (!stateOf(id).isActive &&
            stateOf(id).phase != DownloadPhase.complete)
          id,
    ];
    if (todo.isEmpty) return;
    final now = DateTime.now();
    for (final (i, id) in todo.indexed) {
      _states[id] = DownloadState(
        phase: DownloadPhase.waiting,
        createdAt: now.add(Duration(milliseconds: i)),
      );
    }
    notifyListeners();
    await _askNotificationPermission();
    // Fiches des séries, demandées une seule fois pour toute une saison
    final series = <String, Map<String, dynamic>?>{};
    for (final id in todo) {
      // Annulé entre-temps : on passe au suivant
      if (_states[id]?.phase != DownloadPhase.waiting) continue;
      await _enqueue(api, userId, id, series);
    }
  }

  /// Récupère la fiche de l'élément (et celle de sa série, gardée dans
  /// [series]), puis le met dans la file.
  Future<void> _enqueue(
    JellyfinApi api,
    String userId,
    String itemId,
    Map<String, Map<String, dynamic>?> series,
  ) async {
    final createdAt = _states[itemId]?.createdAt;
    DownloadInfo info;
    try {
      info = DownloadInfo.fromItemJson(
        await api.getItemJson(userId: userId, itemId: itemId),
      );
    } on JellyfinException catch (e) {
      if (!_states.containsKey(itemId)) return;
      _update(
        itemId,
        DownloadState(
          phase: DownloadPhase.failed,
          error: e.message,
          createdAt: createdAt,
        ),
      );
      return;
    }
    // Épisode : résumé et années de la série, pour sa fiche hors ligne
    final seriesId = info.seriesId;
    if (info.isEpisode && seriesId != null) {
      if (!series.containsKey(seriesId)) {
        try {
          series[seriesId] = await api.getItemJson(
            userId: userId,
            itemId: seriesId,
          );
        } on JellyfinException {
          // Pas grave : la fiche hors ligne sera juste moins complète
          series[seriesId] = null;
        }
      }
      final seriesJson = series[seriesId];
      if (seriesJson != null) info = info.withSeries(seriesJson);
    }
    // Annulé pendant qu'on attendait le serveur
    if (!_states.containsKey(itemId)) return;

    // Un ancien essai raté ne doit pas gêner le nouveau
    await FileDownloader().database.deleteRecordWithId(itemId);
    final task = DownloadTask(
      taskId: itemId,
      url: api.downloadUrl(itemId),
      headers: api.streamHeaders,
      baseDirectory: _baseDirectory,
      directory: _directory,
      filename: info.fileName,
      group: _mediaGroup,
      updates: Updates.statusAndProgress,
      requiresWiFi: true,
      allowPause: true,
      retries: 5,
      displayName: info.displayName,
      metaData: jsonEncode(info.toJson()),
      creationTime: createdAt,
    );
    _update(
      itemId,
      DownloadState(
        phase: DownloadPhase.waiting,
        info: info,
        createdAt: createdAt,
      ),
    );
    if (!await FileDownloader().enqueue(task)) {
      _update(
        itemId,
        DownloadState(
          phase: DownloadPhase.failed,
          info: info,
          error: 'Le téléchargement n\'a pas pu démarrer.',
          createdAt: createdAt,
        ),
      );
      return;
    }
    _downloadExtras(api, info);
  }

  /// Affiche, image de fond, vignette et sous-titres séparés : petits
  /// fichiers, sans notification.
  void _downloadExtras(JellyfinApi api, DownloadInfo info) {
    final posterUrl = api.posterUrl(info.posterItem, width: 400);
    final backdropUrl = info.backdropItemId == null
        ? null
        : api.imageUrl(
            itemId: info.backdropItemId!,
            type: 'Backdrop',
            tag: info.backdropTag,
            width: 1280,
          );
    final thumbUrl = api.imageUrl(
      itemId: info.itemId,
      type: 'Primary',
      tag: info.imageTag,
      width: 480,
    );
    final extras = [
      if (posterUrl != null) (posterUrl, _posterFile(info.itemId)),
      if (backdropUrl != null) (backdropUrl, _backdropFile(info.itemId)),
      if (thumbUrl != null) (thumbUrl, _thumbFile(info.itemId)),
      for (final track in info.externalSubtitles)
        (
          api.subtitleFileUrl(
            itemId: info.itemId,
            mediaSourceId: info.mediaSourceId,
            index: track.index,
          ),
          _subtitleFile(info.itemId, track.index),
        ),
    ];
    for (final (url, filename) in extras) {
      FileDownloader().enqueue(
        DownloadTask(
          taskId: filename,
          url: url,
          headers: api.streamHeaders,
          baseDirectory: _baseDirectory,
          directory: _directory,
          filename: filename,
          group: _extrasGroup,
          updates: Updates.none,
          requiresWiFi: true,
          retries: 3,
        ),
      );
    }
  }

  /// Met en pause un téléchargement en cours.
  Future<void> pause(String itemId) async {
    final task = await _taskOf(itemId);
    if (task != null) await FileDownloader().pause(task);
  }

  /// Reprend un téléchargement en pause là où il s'était arrêté
  /// (ou depuis le début si le serveur ne le permet pas).
  Future<void> resume(String itemId) async {
    final task = await _taskOf(itemId);
    if (task == null) return;
    if (!await FileDownloader().resume(task)) {
      await FileDownloader().enqueue(task);
    }
  }

  /// Tâche enregistrée pour cet élément (null si inconnue).
  Future<DownloadTask?> _taskOf(String itemId) async {
    final task = (await FileDownloader().database.recordForId(itemId))?.task;
    return task is DownloadTask ? task : null;
  }

  /// Annule un téléchargement en cours, ou supprime un téléchargement
  /// terminé : fichiers effacés du téléphone.
  Future<void> remove(String itemId) => removeAll([itemId]);

  /// Comme [remove], pour plusieurs éléments à la fois (ex. une saison).
  Future<void> removeAll(Iterable<String> itemIds) async {
    await init();
    final removed = {for (final id in itemIds) id: _states.remove(id)?.info};
    notifyListeners();

    final downloader = FileDownloader();
    for (final MapEntry(key: itemId, value: info) in removed.entries) {
      await downloader.cancelTaskWithId(itemId);
      await downloader.database.deleteRecordWithId(itemId);
      final names = [
        if (info != null) info.fileName,
        _posterFile(itemId),
        _backdropFile(itemId),
        _thumbFile(itemId),
        for (final track in info?.externalSubtitles ?? const []) ...[
          _subtitleFile(itemId, track.index),
        ],
      ];
      for (final name in names) {
        await downloader.cancelTaskWithId(name);
        await _deleteFile(name);
      }
    }
  }

  /// Comment lire l'élément depuis le téléphone, s'il est entièrement
  /// téléchargé (null sinon : lecture depuis le serveur).
  Future<PlaybackInfo?> localPlayback(String itemId) async {
    await init();
    final state = stateOf(itemId);
    final info = state.info;
    if (state.phase != DownloadPhase.complete || info == null) return null;
    final video = await _filePath(info.fileName);
    if (!File(video).existsSync()) return null;
    final subtitles = <int, String>{};
    for (final track in info.externalSubtitles) {
      final path = await _filePath(_subtitleFile(itemId, track.index));
      if (File(path).existsSync()) subtitles[track.index] = path;
    }
    return info.localPlaybackInfo(video, subtitleFiles: subtitles);
  }

  /// Fichiers d'images gardés sur le téléphone (null avant [init]). Le
  /// fichier peut manquer (image absente sur le serveur, ancien
  /// téléchargement) : prévoir une image de secours.
  File? posterFile(String itemId) => _localFile(_posterFile(itemId));
  File? backdropFile(String itemId) => _localFile(_backdropFile(itemId));
  File? thumbFile(String itemId) => _localFile(_thumbFile(itemId));

  /// Affiche gardée sur le téléphone pour un film ou une série (celle
  /// téléchargée avec l'un de ses épisodes). Null s'il n'y en a pas.
  File? localPoster(String itemId) => _existing(itemId, _posterFile);

  /// Image de fond gardée pour un film ou une série (null s'il n'y en a pas).
  File? localBackdrop(String itemId) => _existing(itemId, _backdropFile);

  /// Fichier [name] de l'élément s'il existe, sinon celui d'un épisode
  /// téléchargé de cette série.
  File? _existing(String itemId, String Function(String) name) {
    final ids = [
      itemId,
      for (final MapEntry(key: id, value: state) in _states.entries)
        if (state.info?.seriesId == itemId) id,
    ];
    for (final id in ids) {
      final file = _localFile(name(id));
      if (file != null && file.existsSync()) return file;
    }
    return null;
  }

  File? _localFile(String name) {
    final directory = _directoryPath;
    return directory == null
        ? null
        : File('$directory${Platform.pathSeparator}$name');
  }

  // ---------- Suivi des téléchargements ----------

  void _onUpdate(TaskUpdate update) {
    final task = update.task;
    if (task.group != _mediaGroup) return;
    final current = stateOf(task.taskId);
    final info = current.info ?? _infoOf(task);
    switch (update) {
      case TaskStatusUpdate(:final status, :final exception):
        if (status == TaskStatus.canceled) {
          if (_states.remove(task.taskId) != null) notifyListeners();
          return;
        }
        _update(
          task.taskId,
          current.copyWith(
            phase: _phaseOf(status),
            progress: status == TaskStatus.complete ? 1 : null,
            info: info,
            error: _errorOf(status, exception),
          ),
        );
      case TaskProgressUpdate(:final progress, :final expectedFileSize):
        // Valeurs négatives : codes spéciaux (échec, pause…) déjà reçus
        // par ailleurs dans les changements d'état
        if (progress < 0) return;
        _update(
          task.taskId,
          current.copyWith(
            phase: DownloadPhase.running,
            progress: progress.clamp(0.0, 1.0),
            expectedSize: expectedFileSize > 0 ? expectedFileSize : null,
            info: info,
          ),
        );
    }
  }

  void _update(String itemId, DownloadState state) {
    _states[itemId] = state;
    notifyListeners();
  }

  static DownloadPhase _phaseOf(TaskStatus status) => switch (status) {
    TaskStatus.enqueued || TaskStatus.waitingToRetry => DownloadPhase.waiting,
    TaskStatus.running => DownloadPhase.running,
    TaskStatus.paused => DownloadPhase.paused,
    TaskStatus.complete => DownloadPhase.complete,
    TaskStatus.failed || TaskStatus.notFound => DownloadPhase.failed,
    TaskStatus.canceled => DownloadPhase.none,
  };

  /// Message lisible en cas d'échec (null sinon).
  static String? _errorOf(TaskStatus status, TaskException? exception) {
    if (status == TaskStatus.notFound) {
      return 'Fichier introuvable sur le serveur.';
    }
    if (status != TaskStatus.failed) return null;
    if (exception case TaskHttpException(:final httpResponseCode)
        when httpResponseCode == 401 || httpResponseCode == 403) {
      return 'Ton compte Jellyfin n\'a pas le droit de télécharger.';
    }
    return 'Le téléchargement a échoué.';
  }

  static DownloadInfo? _infoOf(Task task) {
    try {
      return DownloadInfo.fromJson(
        jsonDecode(task.metaData) as Map<String, dynamic>,
      );
    } on Object {
      return null;
    }
  }

  // ---------- Fichiers ----------

  static String _posterFile(String itemId) => '$itemId.poster.jpg';

  static String _backdropFile(String itemId) => '$itemId.backdrop.jpg';

  static String _thumbFile(String itemId) => '$itemId.thumb.jpg';

  static String _subtitleFile(String itemId, int index) =>
      '$itemId.sub$index.srt';

  /// Chemin complet d'un fichier du dossier des téléchargements.
  static Future<String> _filePath(String filename) => DownloadTask(
    url: 'https://localhost',
    baseDirectory: _baseDirectory,
    directory: _directory,
    filename: filename,
  ).filePath();

  static Future<void> _deleteFile(String filename) async {
    final file = File(await _filePath(filename));
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Déjà effacé ou inaccessible : rien de plus à faire
    }
  }

  /// Demande (une fois) le droit d'afficher la progression en notification.
  static Future<void> _askNotificationPermission() async {
    final permissions = FileDownloader().permissions;
    const type = PermissionType.notifications;
    try {
      if (await permissions.status(type) != PermissionStatus.granted) {
        await permissions.request(type);
      }
    } on Object {
      // Refusé ou indisponible : le téléchargement se fait quand même
    }
  }
}
