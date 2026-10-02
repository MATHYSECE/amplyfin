import 'languages.dart';
import 'media_track.dart';
import 'player_codecs.dart';

/// Pistes choisies pour une lecture, par leur numéro sur le serveur.
class TrackSelection {
  const TrackSelection({this.audioIndex, this.subtitleIndex});

  /// Piste audio (null = celle choisie par le serveur).
  final int? audioIndex;

  /// Sous-titres ([noSubtitles] = aucun, null = choix du serveur).
  final int? subtitleIndex;

  /// Valeur « pas de sous-titres », comme pour le serveur.
  static const noSubtitles = -1;
}

/// Choix par langue, valable pour toute une série : appliqué à chaque
/// épisode, dont les pistes ne sont pas forcément dans le même ordre.
class LanguagePreference {
  const LanguagePreference({this.audioLanguage, this.subtitleLanguage});

  /// Relit un choix enregistré.
  factory LanguagePreference.fromJson(Map<String, dynamic> json) =>
      LanguagePreference(
        audioLanguage: json['audio'] as String?,
        subtitleLanguage: json['subtitles'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'audio': audioLanguage,
    'subtitles': subtitleLanguage,
  };

  /// Langue audio (null = réglage par défaut de Jellyfin).
  final String? audioLanguage;

  /// Langue des sous-titres ([noSubtitles] = aucun, null = réglage par défaut).
  final String? subtitleLanguage;

  static const noSubtitles = 'none';

  /// Trouve, dans les pistes d'un épisode, celles qui correspondent aux
  /// langues choisies. Langue absente de l'épisode : choix du serveur.
  /// Les sous-titres que le lecteur ne sait pas afficher ([player]) sont
  /// ignorés.
  TrackSelection resolve(
    List<MediaTrack> tracks, {
    PlayerCodecs player = PlayerCodecs.builtIn,
  }) {
    int? audio;
    if (audioLanguage != null) {
      final same = tracks.where(
        (t) => t.type == TrackType.audio && t.language == audioLanguage,
      );
      // La piste « par défaut » d'abord (évite une piste de commentaires)
      audio = (same.where((t) => t.isDefault).firstOrNull ?? same.firstOrNull)
          ?.index;
    }

    int? subtitle;
    if (subtitleLanguage == noSubtitles) {
      subtitle = TrackSelection.noSubtitles;
    } else if (subtitleLanguage != null) {
      final same = tracks.where(
        (t) =>
            t.type == TrackType.subtitle &&
            t.language == subtitleLanguage &&
            player.showsSubtitle(t),
      );
      // Sous-titres complets de préférence, forcés s'il n'y a que ça
      subtitle =
          (same.where((t) => !t.isForced).firstOrNull ?? same.firstOrNull)
              ?.index;
    }
    return TrackSelection(audioIndex: audio, subtitleIndex: subtitle);
  }

  /// Texte affiché pour la langue audio choisie.
  String get audioLabel =>
      audioLanguage == null ? 'Par défaut' : languageName(audioLanguage);

  /// Texte affiché pour les sous-titres choisis.
  String get subtitleLabel => switch (subtitleLanguage) {
    null => 'Par défaut',
    noSubtitles => 'Aucun',
    final language => languageName(language),
  };
}

/// Langues présentes dans des pistes d'un type, dans leur ordre d'apparition.
List<String> languagesOf(Iterable<MediaTrack> tracks, TrackType type) {
  final languages = <String>[];
  for (final track in tracks) {
    final language = track.language;
    if (track.type == type &&
        language != null &&
        !languages.contains(language)) {
      languages.add(language);
    }
  }
  return languages;
}
