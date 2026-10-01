/// Profil de l'appareil envoyé au serveur avec POST /Items/{id}/PlaybackInfo :
/// il dit ce que le lecteur sait lire, et donc si le serveur doit convertir.
///
/// Le lecteur (media_kit, basé sur mpv) lit presque tout. Pour les formats
/// lourds (H.264, HEVC, AV1, VP9), on annonce ce que la puce vidéo du
/// téléphone décode vraiment (définition, 10 bits) : au-delà, le serveur
/// convertit dès le départ, au lieu d'un échec en pleine lecture.
library;

import '../models/device_decoders.dart';

/// Débit maximum annoncé en qualité originale : 1 Gb/s, soit « pas de limite »
/// en pratique (une 4K d'origine dépasse rarement 100 Mb/s).
const originalMaxBitrate = 1000000000;

/// Conteneurs lus directement par le lecteur.
const _directPlayContainers = [
  'mkv',
  'webm',
  'mp4',
  'm4v',
  'mov',
  'avi',
  'ts',
  'm2ts',
  'mpegts',
  'wmv',
  'asf',
  'flv',
  'ogv',
  '3gp',
];

/// Formats légers et anciens : le processeur les décode sans peine.
const _lightVideoCodecs = [
  'mpeg1video',
  'mpeg2video',
  'mpeg4',
  'msmpeg4v1',
  'msmpeg4v2',
  'msmpeg4v3',
  'h263',
  'vc1',
  'wmv3',
  'vp8',
  'theora',
];

/// Types d'image lus directement. Le Dolby Vision « pur » (profil 5, « DOVI »)
/// n'y est pas : le lecteur l'afficherait avec de fausses couleurs (violet,
/// vert), le serveur le convertit donc. Le Dolby Vision avec une base HDR10,
/// HLG ou SDR (profils 7 et 8) est lu comme cette base.
const _videoRangeTypes = [
  'Unknown',
  'SDR',
  'HDR10',
  'HDR10Plus',
  'HLG',
  'DOVIWithHDR10',
  'DOVIWithHDR10Plus',
  'DOVIWithHLG',
  'DOVIWithSDR',
  'DOVIWithEL',
  'DOVIWithELHDR10Plus',
];

/// Sous-titres intégrés au fichier et affichés par le lecteur lui-même :
/// le serveur n'a pas besoin de les « incruster » dans l'image.
const _embeddedSubtitles = [
  'srt',
  'subrip',
  'ass',
  'ssa',
  'vtt',
  'webvtt',
  'mov_text',
  'pgs',
  'pgssub',
  'dvdsub',
  'dvbsub',
  'sub',
];

/// Sous-titres livrés dans un fichier à part : uniquement les formats que le
/// serveur sait produire (il refuse par exemple « subrip », il faut « srt »).
const _externalSubtitles = ['srt', 'ass', 'ssa', 'vtt'];

/// Construit le profil. [maxBitrate] : débit maximum accepté, en bits/s.
/// [maxWidth] : largeur d'image maximum, pour forcer une définition réduite.
/// [decoders] : ce que la puce vidéo de l'appareil sait décoder.
Map<String, dynamic> buildDeviceProfile({
  required int maxBitrate,
  int? maxWidth,
  DeviceDecoders decoders = const DeviceDecoders(),
}) {
  final known = decoders.codecs != null;
  // Limites imposées à toutes les vidéos : au-delà, le serveur convertit
  final videoConditions = [
    if (maxWidth != null) _lessThanOrEqual('Width', maxWidth),
    if (!decoders.allow10Bit) _lessThanOrEqual('VideoBitDepth', 8),
    {
      'Condition': 'EqualsAny',
      'Property': 'VideoRangeType',
      'Value': _videoRangeTypes.join('|'),
      'IsRequired': false,
    },
  ];
  // Conversion : en HEVC seulement si la puce le décode
  final hevcOutput = !known || decoders.codecs!['hevc']!.hardware;
  return {
    'Name': 'Amplyfin',
    'MaxStreamingBitrate': maxBitrate,
    'MaxStaticBitrate': maxBitrate,
    'DirectPlayProfiles': [
      {
        'Type': 'Video',
        'Container': _directPlayContainers.join(','),
        // Puce inconnue : codecs vides = tous les codecs acceptés
        if (known)
          'VideoCodec': [...heavyVideoCodecs, ..._lightVideoCodecs].join(','),
      },
    ],
    // Secours, ou qualité réduite choisie : flux HLS converti par le serveur
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'hls',
        'Context': 'Streaming',
        'VideoCodec': hevcOutput ? 'h264,hevc' : 'h264',
        'AudioCodec': 'aac,mp3,ac3,eac3',
        'MinSegments': 1,
      },
    ],
    'CodecProfiles': [
      {'Type': 'Video', 'Conditions': videoConditions},
      // Formats lourds : définition et 10 bits selon la puce
      if (known)
        for (final codec in heavyVideoCodecs)
          {
            'Type': 'Video',
            'Codec': codec,
            'Conditions': [
              _lessThanOrEqual('Width', decoders.maxWidthFor(codec)),
              if (!decoders.tenBitFor(codec))
                _lessThanOrEqual('VideoBitDepth', 8),
            ],
          },
    ],
    'SubtitleProfiles': [
      for (final format in _embeddedSubtitles)
        {'Format': format, 'Method': 'Embed'},
      for (final format in _externalSubtitles)
        {'Format': format, 'Method': 'External'},
    ],
  };
}

/// Condition « [property] ≤ [value] » d'un profil de codec.
Map<String, dynamic> _lessThanOrEqual(String property, int value) => {
  'Condition': 'LessThanEqual',
  'Property': property,
  'Value': '$value',
  'IsRequired': true,
};
