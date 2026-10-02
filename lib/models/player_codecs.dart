/// Ce que le lecteur (media_kit) sait décoder lui-même.
///
/// Le son et les sous-titres ne passent jamais par la puce du téléphone :
/// le lecteur embarque ses propres décodeurs (ffmpeg). Ce qui manque à cette
/// liste (le son TrueHD, les sous-titres PGS…) ne peut donc pas être lu tel
/// quel, quel que soit l'appareil.
library;

import 'dart:convert';

import 'media_track.dart';

/// Formats audio affichés sur la page « Ce que ton appareil sait lire »
/// (noms du serveur → nom lisible).
const audioCodecNames = {
  'aac': 'AAC',
  'ac3': 'Dolby Digital (AC3)',
  'eac3': 'Dolby Digital Plus (E-AC3)',
  'truehd': 'Dolby TrueHD',
  'dts': 'DTS et DTS-HD',
  'flac': 'FLAC',
  'opus': 'Opus',
  'mp3': 'MP3',
};

/// Formats audio annoncés au serveur s'ils sont lus (noms du serveur, qui
/// sont aussi ceux du lecteur). Les « pcm_… » sont ajoutés à part.
const _knownAudioCodecs = [
  'aac',
  'ac3',
  'eac3',
  'truehd',
  'mlp',
  'dts',
  'flac',
  'alac',
  'opus',
  'vorbis',
  'mp3',
  'mp2',
  'mp1',
  'wmav1',
  'wmav2',
  'wmapro',
  'wmalossless',
  'ape',
  'wavpack',
  'tta',
];

/// Liste connue d'avance (media_kit 1.2.6, la même sur Android et iPhone).
/// Son : pas de TrueHD.
const _builtInAudio = [
  'aac',
  'ac3',
  'eac3',
  'dts',
  'flac',
  'alac',
  'opus',
  'vorbis',
  'mp1',
  'mp2',
  'mp3',
  'wmav1',
  'wmav2',
  'wmapro',
  'wmalossless',
  'ape',
  'wavpack',
  'tta',
  'pcm_s16le',
  'pcm_s24le',
  'pcm_bluray',
];

/// Vidéo : pas de VC-1.
const _builtInVideo = [
  'h264',
  'hevc',
  'av1',
  'vp9',
  'vp8',
  'mpeg1video',
  'mpeg2video',
  'mpeg4',
  'msmpeg4v1',
  'msmpeg4v2',
  'msmpeg4v3',
  'h263',
  'wmv3',
  'theora',
];

/// Sous-titres : pas de PGS.
const _builtInSubtitles = [
  'subrip',
  'ass',
  'ssa',
  'webvtt',
  'mov_text',
  'dvd_subtitle',
  'dvb_subtitle',
];

/// Noms du serveur qui diffèrent de ceux du lecteur.
const _playerNames = {
  'pgssub': 'hdmv_pgs_subtitle',
  'pgs': 'hdmv_pgs_subtitle',
  'dvdsub': 'dvd_subtitle',
  'dvbsub': 'dvb_subtitle',
  'srt': 'subrip',
  'vtt': 'webvtt',
};

/// Sous-titres en images : impossibles à convertir en texte, il faut
/// que le lecteur sache les dessiner.
const _imageSubtitles = {'hdmv_pgs_subtitle', 'dvd_subtitle', 'dvb_subtitle'};

class PlayerCodecs {
  const PlayerCodecs(this.names, {this.fromPlayer = false});

  /// Lit la réponse du lecteur à « decoder-list » (liste JSON d'objets
  /// avec un champ « codec »). Null si la réponse est illisible.
  static PlayerCodecs? fromDecoderList(String text) {
    try {
      final list = jsonDecode(text);
      if (list is! List) return null;
      final names = {
        for (final entry in list)
          if (entry is Map && entry['codec'] is String)
            (entry['codec'] as String).toLowerCase(),
      };
      return names.isEmpty ? null : PlayerCodecs(names, fromPlayer: true);
    } on FormatException {
      return null;
    }
  }

  /// Liste connue d'avance (version de media_kit utilisée, la même sur
  /// Android et iPhone), si le lecteur ne répond pas.
  static const builtIn = PlayerCodecs({
    ..._builtInAudio,
    ..._builtInVideo,
    ..._builtInSubtitles,
  });

  /// Noms des formats décodés, en minuscules.
  final Set<String> names;

  /// Vrai si la liste vient du lecteur lui-même (sinon : [builtIn]).
  final bool fromPlayer;

  /// Vrai si le lecteur décode ce format (nom du serveur ou du lecteur).
  bool decodes(String codec) {
    final name = codec.toLowerCase();
    return names.contains(_playerNames[name] ?? name);
  }

  /// Formats audio lus, à annoncer au serveur.
  List<String> get audioCodecs => [
    for (final codec in _knownAudioCodecs)
      if (decodes(codec)) codec,
    for (final name in names.toList()..sort())
      if (name.startsWith('pcm_')) name,
  ];

  /// Vrai si la piste audio est lue telle quelle (format inconnu : on
  /// essaie).
  bool playsAudio(MediaTrack track) {
    final codec = track.codec;
    return codec == null || decodes(codec);
  }

  /// Faux pour des sous-titres en images que le lecteur ne sait pas
  /// dessiner (PGS) : le serveur devrait les incruster dans l'image, ce qui
  /// demande de convertir toute la vidéo. Les sous-titres en texte sont
  /// toujours affichables (le serveur les livre en SRT au besoin).
  bool showsSubtitle(MediaTrack track) {
    final codec = track.codec?.toLowerCase();
    if (codec == null) return true;
    final name = _playerNames[codec] ?? codec;
    return !_imageSubtitles.contains(name) || names.contains(name);
  }
}
