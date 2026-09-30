import 'languages.dart';
import 'media_quality.dart';

/// Type de piste qu'on peut choisir.
enum TrackType { audio, subtitle }

/// Une piste audio ou de sous-titres d'un fichier vidéo
/// (élément « MediaStreams » renvoyé par le serveur).
class MediaTrack {
  const MediaTrack({
    required this.index,
    required this.type,
    this.language,
    this.codec,
    this.profile,
    this.channels,
    this.title,
    this.isForced = false,
    this.isDefault = false,
    this.isExternal = false,
    this.deliveryMethod,
    this.deliveryUrl,
  });

  /// Lit une piste. Null si ce n'est ni de l'audio ni des sous-titres.
  static MediaTrack? tryParse(Map<String, dynamic> json) {
    final type = switch (json['Type']) {
      'Audio' => TrackType.audio,
      'Subtitle' => TrackType.subtitle,
      _ => null,
    };
    final index = json['Index'] as int?;
    if (type == null || index == null) return null;
    return MediaTrack(
      index: index,
      type: type,
      language: normalizeLanguage(json['Language'] as String?),
      codec: json['Codec'] as String?,
      profile: json['Profile'] as String?,
      channels: json['Channels'] as int?,
      title: json['Title'] as String?,
      isForced: json['IsForced'] == true,
      isDefault: json['IsDefault'] == true,
      isExternal: json['IsExternal'] == true,
      deliveryMethod: json['DeliveryMethod'] as String?,
      deliveryUrl: json['DeliveryUrl'] as String?,
    );
  }

  /// Numéro de la piste pour le serveur (« Index »).
  final int index;
  final TrackType type;

  /// Code de langue unifié (« fre », « eng »…), null si inconnu.
  final String? language;
  final String? codec;
  final String? profile;
  final int? channels;

  /// Titre donné dans le fichier (ex. « Commentaires »), souvent vide.
  final String? title;

  /// Sous-titres « forcés » : seulement les passages en langue étrangère.
  final bool isForced;

  /// Piste marquée « par défaut » dans le fichier.
  final bool isDefault;

  /// Sous-titres dans un fichier à part (ex. un .srt à côté de la vidéo).
  final bool isExternal;

  /// Comment le serveur livre les sous-titres (réponse PlaybackInfo) :
  /// « Embed » (dans la vidéo), « External » (adresse à part), « Encode »
  /// (incrustés dans l'image)…
  final String? deliveryMethod;

  /// Adresse (partielle) des sous-titres livrés à part.
  final String? deliveryUrl;

  String get languageLabel => languageName(language);

  /// Nom affiché dans les menus :
  /// « Français · E-AC3 5.1 », « Anglais (forcés) · SRT »…
  String get label {
    final details = type == TrackType.audio
        ? MediaQuality(
            audioCodec: codec,
            audioProfile: profile,
            audioChannels: channels,
          ).audioLabel
        : _subtitleFormat;
    final name = isForced ? '$languageLabel (forcés)' : languageLabel;
    final extraTitle = (title != null && title!.trim().isNotEmpty)
        ? title!.trim()
        : null;
    return [name, ?details, ?extraTitle].join(' · ');
  }

  /// Format des sous-titres, lisible.
  String? get _subtitleFormat => switch (codec?.toLowerCase()) {
    null => null,
    'subrip' || 'srt' => 'SRT',
    'ass' => 'ASS',
    'ssa' => 'SSA',
    'webvtt' || 'vtt' => 'VTT',
    'mov_text' => 'Texte',
    'pgssub' || 'hdmv_pgs_subtitle' || 'pgs' => 'PGS',
    'dvdsub' || 'dvd_subtitle' => 'VobSub',
    final other => other.toUpperCase(),
  };
}

/// Lit les pistes audio et sous-titres d'une liste « MediaStreams ».
List<MediaTrack> tracksFromStreams(List<dynamic>? streams) => [
  for (final stream in streams ?? const [])
    ?MediaTrack.tryParse(stream as Map<String, dynamic>),
];

/// Numéro de la piste pour le lecteur (mpv). Le lecteur compte les pistes
/// intégrées au fichier, type par type, dans l'ordre : 1re piste audio = 1,
/// 2e = 2… Le serveur, lui, numérote toutes les pistes à la suite (vidéo
/// comprise). Null pour une piste externe (chargée à part par son adresse).
int? playerTrackId(List<MediaTrack> tracks, MediaTrack track) {
  if (track.isExternal) return null;
  final sameType =
      tracks.where((t) => t.type == track.type && !t.isExternal).toList()
        ..sort((a, b) => a.index.compareTo(b.index));
  final position = sameType.indexWhere((t) => t.index == track.index);
  return position < 0 ? null : position + 1;
}
