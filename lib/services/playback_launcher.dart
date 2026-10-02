import 'package:flutter/material.dart';

import '../api/device_profile.dart';
import '../api/jellyfin_api.dart';
import '../models/download_info.dart';
import '../models/playback_info.dart';
import '../models/playback_quality.dart';
import '../models/session.dart';
import '../models/track_choice.dart';
import '../screens/player_screen.dart';
import '../widgets/transcode_dialog.dart';
import 'device_capabilities.dart';
import 'download_manager.dart';
import 'offline_progress.dart';
import 'track_preferences.dart';

/// Lance la lecture d'un film ou d'un épisode.
/// Téléchargé : le fichier du téléphone est lu directement (sauf si le
/// lecteur ne sait pas lire son son : le serveur le convertit alors). Sinon,
/// demande d'abord au serveur si la lecture directe est possible ; si non,
/// explique pourquoi et demande à l'utilisateur s'il veut convertir. Seul le
/// son à convertir : pas de question, c'est léger et l'image reste d'origine.
/// [start] : position de départ (reprise de lecture), le début par défaut.
/// Se termine quand on revient du lecteur (ou si on annule) et renvoie
/// l'élément lu en dernier (l'épisode suivant s'il a été enchaîné), null si
/// la lecture n'a pas démarré.
Future<String?> launchPlayback(
  BuildContext context, {
  required JellyfinApi api,
  required Session session,
  required String itemId,
  required String title,
  String? subtitle,
  TrackSelection tracks = const TrackSelection(),
  Duration start = Duration.zero,
}) async {
  final PlaybackInfo info;
  final decoders = await DeviceCapabilities.decoders();
  var local = await DownloadManager.instance.localPlayback(itemId);
  // Son du fichier téléchargé illisible (TrueHD…) : flux du serveur
  final localAudio = local?.track(tracks.audioIndex ?? local.defaultAudioIndex);
  final unreadableSound =
      localAudio != null && !decoders.player.playsAudio(localAudio);
  if (unreadableSound) local = null;
  if (local != null) {
    info = local;
  } else {
    try {
      info = await api.getPlaybackInfo(
        userId: session.userId,
        itemId: itemId,
        quality: PlaybackQuality.original,
        // En cas de conversion, le serveur commence au bon endroit
        start: start,
        // Ce que la puce ne lit pas est converti par le serveur
        decoders: decoders,
        tracks: tracks,
      );
    } on JellyfinException catch (e) {
      if (context.mounted) {
        final message = unreadableSound
            ? 'Le son de ce téléchargement ne peut pas être lu sur cet '
                  'appareil. Connecte-toi au serveur pour qu\'il le convertisse.'
            : e.message;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
      return null;
    }
  }
  if (!context.mounted) return null;

  if (!info.directPlay &&
      !info.convertsOnlyAudio(transcodeVideoCodecs(decoders))) {
    final convert = await showTranscodeDialog(
      context,
      reasonCodes: info.transcodeReasons,
    );
    if (!convert || !context.mounted) return null;
  }

  return Navigator.of(context).push(
    MaterialPageRoute<String>(
      builder: (_) => PlayerScreen(
        api: api,
        session: session,
        itemId: itemId,
        title: title,
        subtitle: subtitle,
        tracks: tracks,
        start: start,
        // Réponse déjà obtenue : le lecteur démarre sans redemander
        initialInfo: info,
      ),
    ),
  );
}

/// Lit un film ou un épisode téléchargé : épisode avec les langues
/// choisies pour sa série, et reprise à la position la plus récente,
/// celle du téléphone ou celle du serveur (s'il répond vite).
Future<void> launchDownloadPlayback(
  BuildContext context, {
  required JellyfinApi api,
  required Session session,
  required DownloadInfo info,
}) async {
  var tracks = const TrackSelection();
  final seriesId = info.seriesId;
  if (info.isEpisode && seriesId != null) {
    final languages = await TrackPreferences().load(seriesId);
    tracks = languages.resolve(
      info.tracks,
      player: DeviceCapabilities.playerCodecs,
    );
  }
  final saved = OfflineProgress.instance.of(info.itemId);
  var start = saved?.resumePosition ?? Duration.zero;
  try {
    final server =
        (await api
                .getItemDetails(userId: session.userId, itemId: info.itemId)
                .timeout(const Duration(seconds: 3)))
            .progress;
    if (saved == null || !phoneIsNewer(saved, server.lastPlayed)) {
      start = server.canResume ? server.position : Duration.zero;
      // Gardée aussi sur le téléphone, pour reprendre hors ligne
      await OfflineProgress.instance.remember(
        info.itemId,
        server,
        runtime: info.runtime,
      );
    }
  } on Exception {
    // Pas de réseau (ou trop lent) : la position du téléphone
  }
  if (!context.mounted) return;
  await launchPlayback(
    context,
    api: api,
    session: session,
    itemId: info.itemId,
    title: info.playerTitle,
    subtitle: info.playerSubtitle,
    tracks: tracks,
    start: start,
  );
}
