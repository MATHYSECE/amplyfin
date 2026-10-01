import 'package:flutter/material.dart';

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
import 'track_preferences.dart';

/// Lance la lecture d'un film ou d'un épisode.
/// Téléchargé : le fichier du téléphone est lu directement. Sinon, demande
/// d'abord au serveur si la lecture directe est possible ; si non, explique
/// pourquoi et demande à l'utilisateur s'il veut convertir.
/// [start] : position de départ (reprise de lecture), le début par défaut.
/// Se termine quand on revient du lecteur (ou si on annule).
Future<void> launchPlayback(
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
  final local = await DownloadManager.instance.localPlayback(itemId);
  if (local != null) {
    info = local;
  } else {
    final emulator = await DeviceCapabilities.isAndroidEmulator();
    try {
      info = await api.getPlaybackInfo(
        userId: session.userId,
        itemId: itemId,
        quality: PlaybackQuality.original,
        // En cas de conversion, le serveur commence au bon endroit
        start: start,
        supports10Bit: !emulator,
        tracks: tracks,
      );
    } on JellyfinException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
  }
  if (!context.mounted) return;

  if (!info.directPlay) {
    final convert = await showTranscodeDialog(
      context,
      reasonCodes: info.transcodeReasons,
    );
    if (!convert || !context.mounted) return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute(
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

/// Lit un film ou un épisode depuis l'écran des téléchargements :
/// épisode avec les langues choisies pour sa série, et reprise là où on
/// s'était arrêté si le serveur répond vite (sinon depuis le début).
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
    tracks = languages.resolve(info.tracks);
  }
  var start = Duration.zero;
  try {
    final details = await api
        .getItemDetails(userId: session.userId, itemId: info.itemId)
        .timeout(const Duration(seconds: 3));
    if (details.progress.canResume) start = details.progress.position;
  } on Exception {
    // Pas de réseau (ou trop lent) : lecture depuis le début
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
