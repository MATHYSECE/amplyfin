import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/playback_info.dart';
import '../models/playback_quality.dart';
import '../models/session.dart';
import '../models/track_choice.dart';
import '../screens/player_screen.dart';
import '../widgets/transcode_dialog.dart';
import 'device_capabilities.dart';
import 'download_manager.dart';

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
