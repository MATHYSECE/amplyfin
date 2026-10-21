import 'package:fvp/fvp.dart';
import 'package:video_player/video_player.dart';

import '../models/media_track.dart';
import 'exo_engine.dart';
import 'video_engine.dart';

/// Moteur vidéo de l'iPhone et de l'iPad : libmdk (paquet fvp), branché
/// sur video_player. Il lit les MKV tels quels (Direct Play), décode avec
/// la puce vidéo (VideoToolbox) et partage l'image avec Flutter en Metal,
/// sans la redessiner ni la recopier comme mpv : bien moins de batterie.
/// Tout le reste (sous-titres SRT, écran allumé, erreurs) est celui
/// d'ExoPlayer, qui passe aussi par video_player.
class MdkEngine extends ExoEngine {
  /// Piste de sous-titres du fichier à lire (n-ième, depuis 0), pour une
  /// vidéo téléchargée lue sans le serveur. Null : aucune.
  int? _fileTrack;

  /// libmdk affiche de lui-même les sous-titres du fichier (MKV), dans sa
  /// propre police : on ne garde que ceux qu'on a choisis, et c'est notre
  /// afficheur qui dessine leur texte (police et taille de l'appli).
  @override
  void prepare(VideoPlayerController controller) {
    // libmdk lit la piste mais ne la dessine pas dans l'image
    controller.setProperty('subtitle', '0');
    _applyFileTrack(controller);
  }

  /// Sous-titres du fichier (vidéo téléchargée) : libmdk les lit et nous
  /// passe le texte. Sinon : comme ExoPlayer (SRT envoyé par le serveur).
  @override
  Future<void> selectSubtitles(SubtitleSource source) async {
    final number = source is EmbeddedSubtitles
        ? playerTrackId(source.all, source.track)
        : null;
    _fileTrack = number == null ? null : number - 1;
    final current = controller;
    if (current != null && current.value.isInitialized) {
      _applyFileTrack(current);
    }
    await super.selectSubtitles(
      source is EmbeddedSubtitles ? const NoSubtitles() : source,
    );
  }

  /// Active la piste [_fileTrack] de [current] (ou aucune) et reçoit son
  /// texte.
  void _applyFileTrack(VideoPlayerController current) {
    clearFileCue();
    final track = _fileTrack;
    if (track == null) {
      current.onSubtitleText(null);
      current.setSubtitleTracks([]);
      return;
    }
    current.onSubtitleText((start, end, text) {
      if (controller != current) return;
      showFileCue(
        Duration(milliseconds: (start * 1000).round()),
        Duration(milliseconds: (end * 1000).round()),
        text,
      );
    });
    current.setSubtitleTracks([track]);
  }

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
