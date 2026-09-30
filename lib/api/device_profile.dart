/// Profil de l'appareil envoyé au serveur avec POST /Items/{id}/PlaybackInfo :
/// il dit ce que le lecteur sait lire, et donc si le serveur doit convertir.
///
/// Le lecteur (media_kit, basé sur mpv) lit presque tout : on annonce donc
/// la lecture directe de tous les formats courants, pour éviter au maximum
/// la conversion (transcodage) par le serveur.
library;

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

/// Sous-titres dans un fichier à part (chargés plus tard, étape 8).
const _externalSubtitles = ['srt', 'subrip', 'ass', 'ssa', 'vtt', 'webvtt'];

/// Construit le profil. [maxBitrate] : débit maximum accepté, en bits/s.
/// [maxWidth] : largeur d'image maximum, pour forcer une définition réduite.
Map<String, dynamic> buildDeviceProfile({
  required int maxBitrate,
  int? maxWidth,
}) {
  return {
    'Name': 'Amplyfin',
    'MaxStreamingBitrate': maxBitrate,
    'MaxStaticBitrate': maxBitrate,
    // Lecture directe : codecs vides = tous les codecs acceptés
    'DirectPlayProfiles': [
      {'Type': 'Video', 'Container': _directPlayContainers.join(',')},
    ],
    // Secours, ou qualité réduite choisie : flux HLS converti par le serveur
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'hls',
        'Context': 'Streaming',
        'VideoCodec': 'h264,hevc',
        'AudioCodec': 'aac,mp3,ac3,eac3',
        'MinSegments': 1,
      },
    ],
    // Qualité réduite : limite de largeur pour toutes les vidéos
    if (maxWidth != null)
      'CodecProfiles': [
        {
          'Type': 'Video',
          'Conditions': [
            {
              'Condition': 'LessThanEqual',
              'Property': 'Width',
              'Value': '$maxWidth',
              'IsRequired': true,
            },
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
