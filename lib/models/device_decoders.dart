/// Ce que la puce vidéo de l'appareil sait décoder (demandé au téléphone),
/// et ce que le lecteur décode lui-même (son, sous-titres).
library;

import 'player_codecs.dart';

/// Formats « lourds » : décodés par la puce vidéo quand elle sait le faire.
/// Noms des codecs comme pour le serveur Jellyfin.
const heavyVideoCodecs = ['h264', 'hevc', 'av1', 'vp9'];

/// Nom affiché de chaque format lourd.
const videoCodecNames = {
  'h264': 'H.264',
  'hevc': 'HEVC (H.265)',
  'av1': 'AV1',
  'vp9': 'VP9',
};

/// Sans la puce, le processeur décode lui-même jusqu'à cette largeur
/// (1080p, en 8 bits) : au-delà, ce serait saccadé.
const softwareMaxWidth = 1920;

/// Ce que la puce sait faire pour un format.
class CodecSupport {
  const CodecSupport({
    this.hardware = false,
    this.maxWidth,
    this.maxHeight,
    this.tenBit = false,
  });

  /// Lu depuis la réponse du code natif.
  factory CodecSupport.fromMap(Map<Object?, Object?> map) => CodecSupport(
    hardware: map['hardware'] == true,
    maxWidth: (map['maxWidth'] as num?)?.toInt(),
    maxHeight: (map['maxHeight'] as num?)?.toInt(),
    tenBit: map['tenBit'] == true,
  );

  /// Vrai si la puce vidéo décode ce format (sinon, le processeur).
  final bool hardware;

  /// Plus grande image décodée par la puce (null : inconnue).
  final int? maxWidth;
  final int? maxHeight;

  /// Vrai si la puce lit aussi la version 10 bits (HDR).
  final bool tenBit;

  /// Définition lisible : « 4K », « 1080p »…
  String? get resolutionLabel {
    final width = maxWidth;
    if (width == null) return null;
    if (width >= 7680) return '8K';
    if (width >= 3840) return '4K';
    if (width >= 2560) return '1440p';
    if (width >= 1920) return '1080p';
    if (width >= 1280) return '720p';
    return '${maxHeight ?? width}p';
  }
}

/// Ce que l'appareil sait décoder, et son écran.
class DeviceDecoders {
  const DeviceDecoders({
    this.codecs,
    this.dolbyVision = false,
    this.hdrScreen = false,
    this.allow10Bit = true,
    this.player = PlayerCodecs.builtIn,
  });

  /// Lu depuis la réponse du code natif. [allow10Bit] : faux sur
  /// l'émulateur (son affichage ne sait pas montrer le 10 bits).
  factory DeviceDecoders.fromMap(
    Map<Object?, Object?> map, {
    bool allow10Bit = true,
    PlayerCodecs player = PlayerCodecs.builtIn,
  }) {
    final codecs = map['codecs'] as Map<Object?, Object?>? ?? const {};
    return DeviceDecoders(
      codecs: {
        for (final codec in heavyVideoCodecs)
          codec: codecs[codec] is Map
              ? CodecSupport.fromMap(codecs[codec]! as Map<Object?, Object?>)
              : const CodecSupport(),
      },
      dolbyVision: map['dolbyVision'] == true,
      hdrScreen: map['hdrScreen'] == true,
      allow10Bit: allow10Bit,
      player: player,
    );
  }

  /// Formats lourds et ce que la puce en fait (null : inconnu, le téléphone
  /// n'a pas répondu ; tout est alors accepté, comme avant).
  final Map<String, CodecSupport>? codecs;

  /// Vrai si la puce a un décodeur Dolby Vision (affiché pour information :
  /// le lecteur montre le Dolby Vision comme du HDR10).
  final bool dolbyVision;

  /// Vrai si l'écran sait afficher le HDR.
  final bool hdrScreen;

  /// Faux pour refuser toute vidéo 10 bits (émulateur).
  final bool allow10Bit;

  /// Formats décodés par le lecteur lui-même (son, sous-titres, vidéos
  /// anciennes).
  final PlayerCodecs player;

  /// Plus grande largeur lue directement pour [codec] (puce, sinon
  /// processeur jusqu'en 1080p).
  int maxWidthFor(String codec) {
    final support = codecs?[codec];
    if (support == null || !support.hardware) return softwareMaxWidth;
    return support.maxWidth ?? softwareMaxWidth;
  }

  /// Vrai si les vidéos 10 bits de [codec] sont lues directement.
  bool tenBitFor(String codec) {
    final support = codecs?[codec];
    return allow10Bit && support != null && support.hardware && support.tenBit;
  }
}
