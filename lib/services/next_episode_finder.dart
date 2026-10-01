import 'dart:async';

import '../api/jellyfin_api.dart';
import '../models/download_info.dart';
import '../models/next_episode.dart';
import 'download_manager.dart';
import 'offline_progress.dart';

/// Délai d'attente du serveur avant de se rabattre sur les téléchargements.
const _serverTimeout = Duration(seconds: 5);

/// Cherche l'épisode qui suit [itemId] : demandé au serveur (épisode
/// téléchargé ou non), sinon, serveur injoignable, le prochain épisode
/// téléchargé de la série. Null pour un film ou le dernier épisode.
Future<NextEpisode?> findNextEpisode(
  JellyfinApi api, {
  required String userId,
  required String itemId,
}) async {
  final local = _downloaded(itemId);
  try {
    var seriesId = local?.seriesId;
    if (seriesId == null) {
      final item = await api
          .getItemJson(userId: userId, itemId: itemId)
          .timeout(_serverTimeout);
      if (item['Type'] != 'Episode') return null;
      seriesId = item['SeriesId'] as String?;
      if (seriesId == null) return null;
    }
    final json = await api
        .getNextEpisode(userId: userId, seriesId: seriesId, itemId: itemId)
        .timeout(_serverTimeout);
    if (json == null) return null;
    final id = json['Id'] as String;
    final tag = (json['ImageTags'] as Map<String, dynamic>?)?['Primary'];
    return NextEpisode.fromJson(
      json,
      imageUrl: api.imageUrl(
        itemId: id,
        type: 'Primary',
        tag: tag as String?,
        width: 480,
      ),
    );
  } on Exception {
    // Serveur injoignable (ou trop lent) : les téléchargements
    if (local == null) return null;
    final downloaded = [
      for (final state in DownloadManager.instance.states.values)
        if (state.phase == DownloadPhase.complete) ?state.info,
    ];
    final next = nextDownloaded(downloaded, local);
    if (next == null) return null;
    return NextEpisode.fromDownload(
      next,
      progress: OfflineProgress.instance.of(next.itemId)?.toWatchProgress(),
      imagePath: DownloadManager.instance.thumbFile(next.itemId)?.path,
    );
  }
}

/// Début du générique de fin de [itemId], s'il est connu du serveur.
Future<Duration?> findOutroStart(JellyfinApi api, String itemId) async {
  try {
    return await api.getOutroStart(itemId).timeout(_serverTimeout);
  } on Exception {
    // Inconnu (ou pas de réseau) : la carte apparaîtra avant la fin
    return null;
  }
}

/// Infos du téléchargement terminé de [itemId] (null s'il n'y en a pas).
DownloadInfo? _downloaded(String itemId) {
  final state = DownloadManager.instance.stateOf(itemId);
  return state.phase == DownloadPhase.complete ? state.info : null;
}
