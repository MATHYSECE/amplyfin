import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';

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
  /// (affiche, sous-titres séparés).
  static const _mediaGroup = 'media';
  static const _extrasGroup = 'extras';

  /// Dossier des téléchargements (non sauvegardé dans iCloud).
  static const _directory = 'downloads';
  static const _baseDirectory = BaseDirectory.applicationSupport;

  final Map<String, DownloadState> _states = {};
  Future<void>? _ready;

  /// État du téléchargement de cet élément (rien si jamais téléchargé).
  DownloadState stateOf(String itemId) =>
      _states[itemId] ?? const DownloadState();

  /// Nombre de téléchargements pas encore terminés.
  int get activeCount => _states.values.where((s) => s.isActive).length;

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
    downloader.updates.listen(_onUpdate);
    await downloader.start();

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
      );
    }
    notifyListeners();
  }

  /// Lance le téléchargement d'un film ou d'un épisode (Wi-Fi uniquement).
  Future<void> start({
    required JellyfinApi api,
    required String userId,
    required String itemId,
  }) async {
    await init();
    final current = stateOf(itemId);
    if (current.isActive || current.phase == DownloadPhase.complete) return;
    _update(itemId, const DownloadState(phase: DownloadPhase.waiting));
    await _askNotificationPermission();

    final DownloadInfo info;
    try {
      info = DownloadInfo.fromItemJson(
        await api.getItemJson(userId: userId, itemId: itemId),
      );
    } on JellyfinException catch (e) {
      _update(
        itemId,
        DownloadState(phase: DownloadPhase.failed, error: e.message),
      );
      return;
    }

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
    );
    _update(itemId, DownloadState(phase: DownloadPhase.waiting, info: info));
    if (!await FileDownloader().enqueue(task)) {
      _update(
        itemId,
        DownloadState(
          phase: DownloadPhase.failed,
          info: info,
          error: 'Le téléchargement n\'a pas pu démarrer.',
        ),
      );
      return;
    }
    _downloadExtras(api, info);
  }

  /// Affiche et sous-titres séparés : petits fichiers, sans notification.
  void _downloadExtras(JellyfinApi api, DownloadInfo info) {
    final posterUrl = api.posterUrl(info.posterItem, width: 400);
    final extras = [
      if (posterUrl != null) (posterUrl, _posterFile(info.itemId)),
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

  /// Annule un téléchargement en cours, ou supprime un téléchargement
  /// terminé : fichiers effacés du téléphone.
  Future<void> remove(String itemId) async {
    await init();
    final info = stateOf(itemId).info;
    _states.remove(itemId);
    notifyListeners();

    final downloader = FileDownloader();
    await downloader.cancelTaskWithId(itemId);
    await downloader.database.deleteRecordWithId(itemId);
    final names = [
      if (info != null) info.fileName,
      _posterFile(itemId),
      for (final track in info?.externalSubtitles ?? const []) ...[
        _subtitleFile(itemId, track.index),
      ],
    ];
    for (final name in names) {
      await downloader.cancelTaskWithId(name);
      await _deleteFile(name);
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
