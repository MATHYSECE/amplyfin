/// Qualité technique du fichier vidéo : définition, codec, HDR, son.
/// Affichée sur la fiche, ex. « 4K · HEVC · HDR10 · E-AC3 5.1 ».
class MediaQuality {
  const MediaQuality({
    this.width,
    this.height,
    this.videoCodec,
    this.videoRange,
    this.audioCodec,
    this.audioProfile,
    this.audioChannels,
  });

  /// Lit la qualité à partir de la fiche (GET /Items/{id}) : pistes du
  /// premier fichier (MediaSources), sinon pistes générales (MediaStreams).
  /// Null si le serveur ne donne aucune piste.
  static MediaQuality? fromItemJson(Map<String, dynamic> json) {
    final sources = json['MediaSources'] as List<dynamic>?;
    final streams =
        (sources != null && sources.isNotEmpty
                ? (sources.first as Map<String, dynamic>)['MediaStreams']
                : json['MediaStreams'])
            as List<dynamic>?;
    if (streams == null || streams.isEmpty) return null;

    final all = streams.cast<Map<String, dynamic>>();
    final video = all.where((s) => s['Type'] == 'Video').firstOrNull;
    final audios = all.where((s) => s['Type'] == 'Audio');
    // Piste audio par défaut, sinon la première
    final audio =
        audios.where((s) => s['IsDefault'] == true).firstOrNull ??
        audios.firstOrNull;
    if (video == null && audio == null) return null;

    return MediaQuality(
      width: video?['Width'] as int?,
      height: video?['Height'] as int?,
      videoCodec: video?['Codec'] as String?,
      videoRange: video?['VideoRangeType'] as String?,
      audioCodec: audio?['Codec'] as String?,
      audioProfile: audio?['Profile'] as String?,
      audioChannels: audio?['Channels'] as int?,
    );
  }

  final int? width;
  final int? height;

  /// Codec vidéo, tel que donné par le serveur (hevc, h264, av1…).
  final String? videoCodec;

  /// Plage dynamique (SDR, HDR10, DOVI…).
  final String? videoRange;

  /// Codec audio (eac3, truehd, dts…).
  final String? audioCodec;

  /// Précision sur le son (ex. « Dolby Atmos », « DTS-HD MA »).
  final String? audioProfile;

  /// Nombre de canaux audio (6 = 5.1).
  final int? audioChannels;

  /// Définition lisible : 4K, 1080p, 720p ou SD.
  /// On regarde la largeur ET la hauteur : un film en 1920×800 est bien du 1080p.
  String? get resolutionLabel {
    final w = width ?? 0;
    final h = height ?? 0;
    if (w == 0 && h == 0) return null;
    if (w >= 3200 || h >= 1800) return '4K';
    if (w >= 1800 || h >= 1000) return '1080p';
    if (w >= 1200 || h >= 700) return '720p';
    return 'SD';
  }

  /// Codec vidéo lisible : HEVC, H.264, AV1…
  String? get videoCodecLabel => switch (videoCodec?.toLowerCase()) {
    null => null,
    'hevc' || 'h265' => 'HEVC',
    'h264' || 'avc' => 'H.264',
    'av1' => 'AV1',
    'vp9' => 'VP9',
    'mpeg2video' => 'MPEG-2',
    'vc1' => 'VC-1',
    final other => other.toUpperCase(),
  };

  /// HDR lisible, ou null pour une vidéo normale (SDR).
  String? get hdrLabel {
    final range = videoRange;
    if (range == null) return null;
    if (range.startsWith('DOVI')) return 'Dolby Vision';
    return switch (range) {
      'HDR10Plus' => 'HDR10+',
      'HDR10' => 'HDR10',
      'HLG' => 'HLG',
      _ => null,
    };
  }

  /// Son lisible : « E-AC3 5.1 », « TrueHD Atmos 7.1 », « AAC Stéréo »…
  String? get audioLabel {
    final codec = switch (audioCodec?.toLowerCase()) {
      null => null,
      'eac3' => 'E-AC3',
      'ac3' => 'AC3',
      'truehd' => 'TrueHD',
      'dts' when (audioProfile ?? '').contains('MA') => 'DTS-HD MA',
      'dts' => 'DTS',
      'aac' => 'AAC',
      'mp3' => 'MP3',
      'flac' => 'FLAC',
      'opus' => 'Opus',
      final other => other.toUpperCase(),
    };
    final atmos = (audioProfile ?? '').contains('Atmos') ? 'Atmos' : null;
    final channels = switch (audioChannels) {
      null => null,
      1 => 'Mono',
      2 => 'Stéréo',
      6 => '5.1',
      8 => '7.1',
      final n => '$n canaux',
    };
    final parts = [?codec, ?atmos, ?channels];
    return parts.isEmpty ? null : parts.join(' ');
  }

  /// Toutes les étiquettes à afficher, dans l'ordre.
  List<String> get labels => [
    ?resolutionLabel,
    ?videoCodecLabel,
    ?hdrLabel,
    ?audioLabel,
  ];
}
