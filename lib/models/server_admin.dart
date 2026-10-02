/// Données de la page « Administration du serveur » (réservée aux
/// administrateurs) : infos du serveur, place des bibliothèques, lectures en
/// cours, journal d'activité.
library;

import 'durations.dart';

/// GET /System/Info.
class ServerInfo {
  const ServerInfo({
    required this.name,
    this.version,
    this.system,
    this.updateAvailable = false,
    this.restartPending = false,
    this.canRestart = true,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    // Champs parfois vides selon le serveur : on ne garde que les remplis
    String? text(String key) {
      final value = (json[key] as String?)?.trim() ?? '';
      return value.isEmpty ? null : value;
    }

    final os = text('OperatingSystemDisplayName') ?? text('OperatingSystem');
    final system = [?os, ?text('SystemArchitecture')].join(' · ');
    return ServerInfo(
      name: text('ServerName') ?? 'Serveur Jellyfin',
      version: text('Version'),
      system: system.isEmpty ? null : system,
      updateAvailable: json['HasUpdateAvailable'] == true,
      restartPending: json['HasPendingRestart'] == true,
      canRestart: json['CanSelfRestart'] != false,
    );
  }

  final String name;
  final String? version;

  /// Système et processeur (ex. « Linux · X64 »).
  final String? system;
  final bool updateAvailable;

  /// Un redémarrage est attendu pour finir une mise à jour.
  final bool restartPending;

  /// Faux si le serveur ne sait pas redémarrer tout seul.
  final bool canRestart;
}

/// Place d'une bibliothèque (GET /System/Info/Storage, « Libraries »).
class LibraryStorage {
  const LibraryStorage({
    required this.name,
    required this.freeBytes,
    required this.usedBytes,
  });

  final String name;
  final int freeBytes;
  final int usedBytes;

  int get totalBytes => freeBytes + usedBytes;

  /// Part occupée, de 0 à 1.
  double get usedFraction => totalBytes == 0 ? 0 : usedBytes / totalBytes;

  /// Lit les bibliothèques ; pour chacune, le disque de son premier dossier.
  static List<LibraryStorage> listFromJson(Map<String, dynamic> json) => [
    for (final library in (json['Libraries'] as List<dynamic>?) ?? [])
      if (((library as Map<String, dynamic>)['Folders'] as List<dynamic>?)
              ?.firstOrNull
          case final Map<String, dynamic> folder)
        LibraryStorage(
          name: (library['Name'] as String?) ?? 'Bibliothèque',
          freeBytes: (folder['FreeSpace'] as num?)?.toInt() ?? 0,
          usedBytes: (folder['UsedSpace'] as num?)?.toInt() ?? 0,
        ),
  ];
}

/// Une lecture en cours sur le serveur (GET /Sessions, avec un élément lu).
class ActiveSession {
  const ActiveSession({
    required this.userName,
    required this.device,
    required this.title,
    this.subtitle,
    this.position = Duration.zero,
    this.runtime,
    this.paused = false,
    this.transcoding = false,
    this.transcodeDetail,
  });

  /// Null si la séance ne lit rien.
  static ActiveSession? fromJson(Map<String, dynamic> json) {
    final item = json['NowPlayingItem'] as Map<String, dynamic>?;
    if (item == null) return null;
    final play = (json['PlayState'] as Map<String, dynamic>?) ?? const {};
    final transcode = json['TranscodingInfo'] as Map<String, dynamic>?;
    final seriesName = item['SeriesName'] as String?;
    final season = item['ParentIndexNumber'] as int?;
    final episode = item['IndexNumber'] as int?;
    final client = json['Client'] as String?;
    final deviceName = json['DeviceName'] as String?;
    return ActiveSession(
      userName: (json['UserName'] as String?) ?? 'Inconnu',
      device: [?deviceName, ?client].join(' · '),
      title: seriesName ?? (item['Name'] as String?) ?? 'Sans titre',
      subtitle: seriesName == null
          ? null
          : [
              if (season != null && episode != null) 'S$season · É$episode',
              ?(item['Name'] as String?),
            ].join(' · '),
      position: ticksToDuration(play['PositionTicks'] as int?) ?? Duration.zero,
      runtime: ticksToDuration(item['RunTimeTicks'] as int?),
      paused: play['IsPaused'] == true,
      transcoding: play['PlayMethod'] == 'Transcode',
      transcodeDetail: transcode == null ? null : _transcodeDetail(transcode),
    );
  }

  final String userName;

  /// Appareil et appli (ex. « iPhone · Amplyfin »).
  final String device;
  final String title;

  /// Épisode : « S2 · É5 · Titre ».
  final String? subtitle;
  final Duration position;
  final Duration? runtime;
  final bool paused;

  /// Vrai si le serveur convertit (sinon lecture directe).
  final bool transcoding;

  /// Ce qui est converti : « Image H.264 · 75 i/s · Intel QSV »…
  final String? transcodeDetail;

  /// Part déjà lue, de 0 à 1 (0 si la durée est inconnue).
  double get fraction {
    final total = runtime;
    if (total == null || total == Duration.zero) return 0;
    return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  static String _transcodeDetail(Map<String, dynamic> info) {
    final videoCopied = info['IsVideoDirect'] == true;
    final audioCopied = info['IsAudioDirect'] == true;
    final video = (info['VideoCodec'] as String?)?.toUpperCase();
    final audio = (info['AudioCodec'] as String?)?.toUpperCase();
    final fps = (info['Framerate'] as num?)?.round();
    final hardware = info['HardwareAccelerationType'] as String?;
    return [
      videoCopied ? 'Image d\'origine' : 'Image ${video ?? 'convertie'}',
      audioCopied ? 'son d\'origine' : 'son ${audio ?? 'converti'}',
      if (!videoCopied && fps != null) '$fps i/s',
      if (!videoCopied && hardware != null && hardware != 'none')
        _hardwareName(hardware),
    ].join(' · ');
  }

  static String _hardwareName(String type) => switch (type.toLowerCase()) {
    'qsv' => 'Intel QSV',
    'nvenc' => 'NVIDIA',
    'vaapi' => 'VA-API',
    'amf' => 'AMD',
    'videotoolbox' => 'VideoToolbox',
    'rkmpp' => 'Rockchip',
    final other => other.toUpperCase(),
  };
}

/// Une ligne du journal d'activité (GET /System/ActivityLog/Entries).
class ActivityEntry {
  const ActivityEntry({
    required this.name,
    this.detail,
    this.date,
    this.isError = false,
  });

  factory ActivityEntry.fromJson(Map<String, dynamic> json) => ActivityEntry(
    name: (json['Name'] as String?) ?? '',
    detail: (json['ShortOverview'] as String?) ?? json['Overview'] as String?,
    date: DateTime.tryParse((json['Date'] as String?) ?? '')?.toLocal(),
    isError: switch (json['Severity']) {
      'Error' || 'Critical' || 'Warning' => true,
      _ => false,
    },
  );

  final String name;
  final String? detail;
  final DateTime? date;

  /// Avertissement ou erreur.
  final bool isError;
}

/// « à l'instant », « il y a 5 min », « il y a 3 h », « il y a 2 j ».
String timeAgo(DateTime date, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(date);
  if (elapsed.inMinutes < 1) return 'à l\'instant';
  if (elapsed.inHours < 1) return 'il y a ${elapsed.inMinutes} min';
  if (elapsed.inDays < 1) return 'il y a ${elapsed.inHours} h';
  return 'il y a ${elapsed.inDays} j';
}
