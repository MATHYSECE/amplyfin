/// Réglages du compte Jellyfin (GET /Users/Me) : langues préférées, et si
/// le compte administre le serveur. Ils sont gardés sur le serveur : toutes
/// les applis Jellyfin du compte les suivent.
library;

import 'languages.dart';

/// Quand afficher les sous-titres (valeurs « SubtitleMode » du serveur).
enum SubtitleMode {
  smart('Smart', 'Automatique', 'Si l\'audio n\'est pas dans ta langue'),
  always('Always', 'Toujours', 'Dès qu\'il y en a dans ta langue'),
  onlyForced(
    'OnlyForced',
    'Passages étrangers seulement',
    'Seulement les sous-titres « forcés »',
  ),
  none('None', 'Jamais', 'Tu les choisis toi-même au besoin'),
  standard('Default', 'Selon le fichier', 'Ceux marqués « par défaut »');

  const SubtitleMode(this.serverName, this.label, this.description);

  /// Nom pour le serveur.
  final String serverName;

  /// Nom affiché et précision.
  final String label;
  final String description;

  static SubtitleMode fromServer(String? name) => SubtitleMode.values
      .firstWhere((m) => m.serverName == name, orElse: () => standard);
}

class UserSettings {
  const UserSettings({
    this.audioLanguage,
    this.subtitleLanguage,
    this.subtitleMode = SubtitleMode.standard,
    this.isAdmin = false,
    this.configuration = const {},
  });

  /// Lit la réponse de GET /Users/Me.
  factory UserSettings.fromMe(Map<String, dynamic> json) {
    final configuration =
        (json['Configuration'] as Map<String, dynamic>?) ?? const {};
    final policy = (json['Policy'] as Map<String, dynamic>?) ?? const {};
    String? language(String key) {
      final code = (configuration[key] as String?)?.trim() ?? '';
      return code.isEmpty ? null : normalizeLanguage(code);
    }

    return UserSettings(
      audioLanguage: language('AudioLanguagePreference'),
      subtitleLanguage: language('SubtitleLanguagePreference'),
      subtitleMode: SubtitleMode.fromServer(
        configuration['SubtitleMode'] as String?,
      ),
      isAdmin: policy['IsAdministrator'] == true,
      configuration: configuration,
    );
  }

  /// Langue audio préférée (null : la piste principale du fichier).
  final String? audioLanguage;

  /// Langue des sous-titres préférée (null : aucune préférence).
  final String? subtitleLanguage;

  final SubtitleMode subtitleMode;

  /// Vrai si le compte administre le serveur.
  final bool isAdmin;

  /// Tous les réglages du compte, tels que le serveur les a donnés : on les
  /// renvoie en entier (le serveur remplace l'ensemble).
  final Map<String, dynamic> configuration;

  /// Copie avec des réglages changés. [clearAudio] / [clearSubtitle] :
  /// retire la préférence de langue.
  UserSettings copyWith({
    String? audioLanguage,
    bool clearAudio = false,
    String? subtitleLanguage,
    bool clearSubtitle = false,
    SubtitleMode? subtitleMode,
  }) => UserSettings(
    audioLanguage: clearAudio ? null : audioLanguage ?? this.audioLanguage,
    subtitleLanguage: clearSubtitle
        ? null
        : subtitleLanguage ?? this.subtitleLanguage,
    subtitleMode: subtitleMode ?? this.subtitleMode,
    isAdmin: isAdmin,
    configuration: configuration,
  );

  /// Réglages complets à renvoyer au serveur (POST /Users/Configuration).
  /// Avec une langue audio choisie, elle passe avant la piste « par défaut »
  /// du fichier.
  Map<String, dynamic> toConfiguration() => {
    ...configuration,
    'AudioLanguagePreference': audioLanguage ?? '',
    'PlayDefaultAudioTrack': audioLanguage == null,
    'SubtitleLanguagePreference': subtitleLanguage ?? '',
    'SubtitleMode': subtitleMode.serverName,
  };
}
