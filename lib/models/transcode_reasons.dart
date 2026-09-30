/// Raisons pour lesquelles le serveur doit convertir un fichier
/// (codes « TranscodeReason » de Jellyfin), traduites en phrases simples.
library;

const _messages = {
  'ContainerNotSupported':
      'Le format du fichier n\'est pas lu par cet appareil.',
  'VideoCodecNotSupported': 'Ton appareil ne sait pas décoder la vidéo.',
  'VideoProfileNotSupported': 'Ton appareil ne sait pas décoder la vidéo.',
  'VideoLevelNotSupported': 'Ton appareil ne sait pas décoder la vidéo.',
  'VideoCodecTagNotSupported': 'Ton appareil ne sait pas décoder la vidéo.',
  'UnknownVideoStreamInfo': 'Le serveur ne connaît pas assez bien la vidéo.',
  'VideoBitDepthNotSupported':
      'Ton appareil ne sait pas lire la vidéo en 10\u00A0bits.',
  'VideoRangeTypeNotSupported':
      'Le type d\'image (HDR, Dolby Vision) n\'est pas pris en charge.',
  'VideoResolutionNotSupported': 'La définition de la vidéo est trop élevée.',
  'VideoFramerateNotSupported':
      'Le nombre d\'images par seconde n\'est pas pris en charge.',
  'RefFramesNotSupported': 'Ton appareil ne sait pas décoder la vidéo.',
  'AnamorphicVideoNotSupported':
      'Le format d\'image (anamorphose) n\'est pas pris en charge.',
  'InterlacedVideoNotSupported':
      'La vidéo est entrelacée, ce qui n\'est pas pris en charge.',
  'VideoRotationNotSupported':
      'La rotation de la vidéo n\'est pas prise en charge.',
  'VideoBitrateNotSupported': 'Le débit de la vidéo est trop élevé.',
  'AudioCodecNotSupported': 'Ton appareil ne sait pas lire le son.',
  'AudioProfileNotSupported': 'Ton appareil ne sait pas lire le son.',
  'AudioChannelsNotSupported':
      'Le nombre de canaux audio n\'est pas pris en charge.',
  'AudioSampleRateNotSupported': 'Ton appareil ne sait pas lire le son.',
  'AudioBitDepthNotSupported': 'Ton appareil ne sait pas lire le son.',
  'AudioBitrateNotSupported': 'Le débit du son est trop élevé.',
  'AudioIsExternal': 'Le son est dans un fichier à part.',
  'SecondaryAudioNotSupported':
      'La piste audio choisie n\'est pas prise en charge.',
  'UnknownAudioStreamInfo': 'Le serveur ne connaît pas assez bien le son.',
  'SubtitleCodecNotSupported':
      'Les sous-titres choisis doivent être incrustés dans l\'image.',
  'ContainerBitrateExceedsLimit':
      'Le débit du fichier dépasse la limite autorisée pour ton compte.',
  'StreamCountExceedsLimit': 'Le fichier contient trop de pistes.',
  'DirectPlayError': 'La lecture directe a échoué.',
};

/// Phrases expliquant les raisons (sans doublon, dans l'ordre reçu).
/// Code inconnu : phrase générale.
List<String> describeTranscodeReasons(Iterable<String> codes) {
  final messages = <String>[];
  for (final code in codes) {
    final message =
        _messages[code] ?? 'Ce fichier ne peut pas être lu tel quel.';
    if (!messages.contains(message)) messages.add(message);
  }
  return messages;
}
