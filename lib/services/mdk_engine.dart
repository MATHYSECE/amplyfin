import 'package:fvp/fvp.dart';

import '../models/media_track.dart';
import 'exo_engine.dart';

/// Moteur vidéo de l'iPhone et de l'iPad : libmdk (paquet fvp), branché
/// sur video_player. Il lit les MKV tels quels (Direct Play), décode avec
/// la puce vidéo (VideoToolbox) et partage l'image avec Flutter en Metal,
/// sans la redessiner ni la recopier comme mpv : bien moins de batterie.
/// Tout le reste (sous-titres SRT, écran allumé, erreurs) est celui
/// d'ExoPlayer, qui passe aussi par video_player.
class MdkEngine extends ExoEngine {
  /// libmdk liste les pistes audio dans l'ordre du fichier : la n-ième
  /// piste audio du serveur est la n-ième ici (numérotées depuis 0).
  @override
  Future<void> selectAudio(List<MediaTrack> all, MediaTrack track) async {
    final current = controller;
    final number = playerTrackId(all, track);
    if (current == null || number == null) return;
    current.setAudioTracks([number - 1]);
  }

  @override
  Future<List<String>> playbackDetails() async {
    final current = controller;
    final video = current?.getMediaInfo()?.video?.firstOrNull?.codec;
    return [
      'Lecteur : libmdk (puce vidéo VideoToolbox en priorité)',
      if (video != null) ...[
        'Vidéo : ${video.codec}',
        'Image : ${video.width} × ${video.height}'
            '${video.formatName == null ? '' : ' · ${video.formatName}'}'
            ' · ${_fps(video.frameRate)} i/s',
      ] else if (current != null && !current.value.size.isEmpty)
        'Image : ${current.value.size.width.round()} × '
            '${current.value.size.height.round()}',
    ];
  }

  static String _fps(double rate) =>
      rate.toStringAsFixed(rate % 1 == 0 ? 0 : 3);
}
