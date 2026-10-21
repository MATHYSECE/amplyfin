import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/media_track.dart';
import 'device_capabilities.dart';
import 'exo_engine.dart';
import 'mdk_engine.dart';
import 'mpv_engine.dart';
import 'tizen_engine.dart';

/// Vrai si cet appareil lit avec ExoPlayer (Android).
bool get usesExoPlayer => defaultTargetPlatform == TargetPlatform.android;

/// Vrai si cet appareil lit avec libmdk (iPhone, iPad).
bool get usesMdk => defaultTargetPlatform == TargetPlatform.iOS;

/// Moteur vidéo : ce dont le lecteur a besoin, quel que soit l'appareil.
/// Chaque appareil branche le meilleur moteur pour lui derrière cette même
/// façade ; le lecteur, ses commandes et ses sous-titres ne parlent qu'à
/// elle.
abstract class VideoEngine {
  /// Le meilleur moteur pour cet appareil : ExoPlayer sur Android (télé,
  /// téléphone, tablette), libmdk sur iPhone et iPad, le lecteur de la télé
  /// sur Samsung, mpv sur PC.
  factory VideoEngine.forDevice() {
    if (usesExoPlayer) return ExoEngine();
    if (usesMdk) return MdkEngine();
    if (DeviceCapabilities.isTizen) return TizenEngine();
    return MpvEngine();
  }

  /// Prépare l'affichage. [refreshRate] : fréquence de l'écran (images par
  /// seconde), utile au lissage des films sur PC.
  Future<void> initialize({required double refreshRate});

  /// La vidéo elle-même, sans commandes ni sous-titres.
  Widget buildVideo();

  /// Ouvre une vidéo (et démarre la lecture).
  Future<void> open(EngineMedia media);

  /// Attend que le moteur connaisse les pistes du fichier (15 s au plus).
  Future<void> waitForTracks();

  /// Choisit la piste audio [track] du fichier ([all] : toutes ses pistes).
  Future<void> selectAudio(List<MediaTrack> all, MediaTrack track);

  /// Choisit les sous-titres.
  Future<void> selectSubtitles(SubtitleSource source);

  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);

  /// Volume du lecteur, de 0 à 1.
  Future<void> setVolume(double volume);

  /// Arrête la vidéo en cours (le moteur oublie ses pistes et sa durée).
  Future<void> stop();

  /// Libère le moteur (arrête d'abord la lecture).
  Future<void> dispose();

  /// Lignes du panneau « Infos de lecture » : lecteur, décodage (puce ou
  /// processeur), format, images perdues.
  Future<List<String>> playbackDetails();

  /// État actuel.
  EngineState get state;

  /// Changements d'état, au fil de la lecture.
  EngineStreams get stream;
}

/// Vidéo à ouvrir : adresse (ou chemin du fichier téléchargé), en-têtes
/// de connexion au serveur et position de départ.
class EngineMedia {
  const EngineMedia(
    this.uri, {
    this.headers = const {},
    this.start = Duration.zero,
  });

  final String uri;
  final Map<String, String> headers;
  final Duration start;
}

/// Sous-titres à afficher.
sealed class SubtitleSource {
  const SubtitleSource();
}

/// Aucun sous-titre.
class NoSubtitles extends SubtitleSource {
  const NoSubtitles();
}

/// Sous-titres choisis par le moteur (ceux du flux converti).
class AutoSubtitles extends SubtitleSource {
  const AutoSubtitles();
}

/// Fichier de sous-titres à part, téléchargé par son adresse.
class ExternalSubtitles extends SubtitleSource {
  const ExternalSubtitles(this.url, {this.title, this.language});

  final String url;
  final String? title;
  final String? language;
}

/// Piste de sous-titres du fichier vidéo ([all] : toutes ses pistes).
class EmbeddedSubtitles extends SubtitleSource {
  const EmbeddedSubtitles(this.all, this.track);

  final List<MediaTrack> all;
  final MediaTrack track;
}

/// Photo de l'état du moteur à un instant donné.
class EngineState {
  const EngineState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffer = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.subtitle = const [],
  });

  final Duration position;

  /// Durée de la vidéo (zéro tant qu'elle n'a pas démarré).
  final Duration duration;

  /// Position jusqu'où la vidéo est déjà chargée.
  final Duration buffer;
  final bool playing;

  /// Vrai quand la vidéo attend des données (roue de chargement).
  final bool buffering;

  /// Lignes de sous-titres affichées en ce moment.
  final List<String> subtitle;
}

/// Changements d'état du moteur.
class EngineStreams {
  const EngineStreams({
    required this.position,
    required this.playing,
    required this.buffering,
    required this.completed,
    required this.subtitle,
    required this.errors,
    required this.decodeFailures,
  });

  final Stream<Duration> position;
  final Stream<bool> playing;
  final Stream<bool> buffering;

  /// Vrai quand la vidéo est arrivée au bout.
  final Stream<bool> completed;
  final Stream<List<String>> subtitle;

  /// Erreurs qui méritent une réaction (déjà triées par le moteur).
  final Stream<EngineError> errors;

  /// L'image ne peut pas s'afficher (décodeur ou affichage impossible) :
  /// le lecteur propose alors de convertir.
  final Stream<void> decodeFailures;
}

/// Erreur signalée par le moteur.
class EngineError {
  const EngineError({required this.detail, this.subtitles = false});

  /// Message technique, déjà nettoyé (sans adresse ni clé de connexion).
  final String detail;

  /// Vrai si seuls les sous-titres à part n'ont pas pu être chargés.
  final bool subtitles;
}
