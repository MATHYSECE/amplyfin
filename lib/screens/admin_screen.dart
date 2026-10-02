import 'dart:async';

import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/durations.dart';
import '../models/file_size.dart';
import '../models/server_admin.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'settings_screen.dart';

/// Page « Administration du serveur » (administrateurs seulement) : infos du
/// serveur et place des bibliothèques, lectures en cours (mises à jour toutes
/// les 5 s), analyse de la bibliothèque, journal d'activité, redémarrer ou
/// éteindre le serveur.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.api});

  final JellyfinApi api;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  static const _refreshInterval = Duration(seconds: 5);

  /// Événements du journal montrés avant « Voir plus ».
  static const _activityPreview = 8;

  ServerInfo? _info;
  List<LibraryStorage> _storage = const [];
  List<ActiveSession>? _sessions;
  List<ActivityEntry>? _activity;
  String? _error;
  Timer? _timer;

  /// Vrai après « Voir plus » : tout le journal chargé est affiché.
  bool _activityExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refreshInterval, (_) => _loadSessions());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        widget.api.getServerInfo(),
        widget.api.getLibraryStorage(),
        widget.api.getActivityLog(),
      ]);
      if (!mounted) return;
      setState(() {
        _info = results[0] as ServerInfo;
        _storage = results[1] as List<LibraryStorage>;
        _activity = results[2] as List<ActivityEntry>;
      });
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    await _loadSessions();
  }

  /// Lectures en cours (une erreur passagère est ignorée : on réessaie au
  /// prochain tour).
  Future<void> _loadSessions() async {
    try {
      final sessions = await widget.api.getActiveSessions();
      if (mounted) setState(() => _sessions = sessions);
    } on JellyfinException {
      // Prochain essai dans 5 s
    }
  }

  /// Lance une action sur le serveur, avec un message de réussite ou
  /// d'erreur.
  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on JellyfinException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _refreshLibrary() => _run(
    widget.api.refreshLibrary,
    'Analyse de la bibliothèque lancée : les nouveautés arrivent d\'ici '
    'quelques minutes.',
  );

  Future<void> _restart() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Redémarrer le serveur ?',
      message:
          'Les lectures en cours, sur tous les appareils, seront coupées le '
          'temps du redémarrage (environ une minute).',
      action: 'Redémarrer',
      cancel: 'Annuler',
    );
    if (confirmed && mounted) {
      await _run(widget.api.restartServer, 'Le serveur redémarre…');
    }
  }

  Future<void> _shutdown() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Éteindre le serveur ?',
      message:
          'Plus personne ne pourra regarder quoi que ce soit, et il faudra '
          'rallumer le serveur à la main (l\'appli ne pourra pas le faire).',
      action: 'Éteindre',
      cancel: 'Annuler',
    );
    if (confirmed && mounted) {
      await _run(widget.api.shutdownServer, 'Le serveur s\'éteint.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final side = AppLayout.isWide(context)
        ? AppLayout.centeredGutter(context)
        : 20.0;
    final info = _info;

    return Scaffold(
      body: GlowBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              side,
              padding.top + 8,
              side,
              padding.bottom + 32,
            ),
            children: [
              const ScreenTitleRow(title: 'Administration du serveur'),
              const SizedBox(height: 20),
              if (_error != null && info == null) ...[
                SettingsPanel(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.cloud_off_rounded),
                      title: Text(_error!),
                      trailing: TextButton(
                        onPressed: _load,
                        child: const Text('Réessayer'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
              ],
              const SettingsSectionTitle('Serveur'),
              if (info == null && _error == null)
                const _Loading()
              else if (info != null)
                _buildInfo(info),
              const SizedBox(height: 22),
              SettingsSectionTitle(
                _sessions == null || _sessions!.isEmpty
                    ? 'Lectures en cours'
                    : 'Lectures en cours · ${_sessions!.length}',
              ),
              _buildSessions(),
              const SizedBox(height: 22),
              const SettingsSectionTitle('Bibliothèque'),
              SettingsPanel(
                children: [
                  SettingsTile(
                    icon: Icons.sync_rounded,
                    title: 'Actualiser la bibliothèque',
                    value: 'Cherche les films et épisodes ajoutés',
                    onTap: _refreshLibrary,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const SettingsSectionTitle('Journal d\'activité'),
              _buildActivity(),
              const SizedBox(height: 22),
              const SettingsSectionTitle('Redémarrer ou éteindre'),
              SettingsPanel(
                children: [
                  if (info?.canRestart ?? true)
                    SettingsTile(
                      icon: Icons.restart_alt_rounded,
                      title: 'Redémarrer le serveur',
                      value: info?.restartPending ?? false
                          ? 'Conseillé : une mise à jour l\'attend'
                          : 'Coupe les lectures environ une minute',
                      onTap: _restart,
                    )
                  else
                    const SettingsTile(
                      icon: Icons.restart_alt_rounded,
                      title: 'Redémarrer le serveur',
                      value: 'Pas possible depuis l\'appli sur ce serveur',
                    ),
                  const Divider(indent: 16, endIndent: 16),
                  SettingsTile(
                    icon: Icons.power_settings_new_rounded,
                    title: 'Éteindre le serveur',
                    value: 'Il faudra le rallumer à la main',
                    onTap: _shutdown,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfo(ServerInfo info) {
    return SettingsPanel(
      children: [
        SettingsTile(
          icon: Icons.dns_rounded,
          title: info.name,
          value: [
            if (info.version != null) 'Jellyfin ${info.version}',
            ?info.system,
          ].join(' · '),
        ),
        if (info.updateAvailable || info.restartPending) ...[
          const Divider(indent: 16, endIndent: 16),
          SettingsTile(
            icon: Icons.system_update_rounded,
            title: info.updateAvailable
                ? 'Mise à jour disponible'
                : 'Redémarrage en attente',
            value: info.updateAvailable
                ? 'À installer sur le serveur'
                : 'Pour finir une mise à jour',
          ),
        ],
        for (final library in _storage) ...[
          const Divider(indent: 16, endIndent: 16),
          _StorageRow(library: library),
        ],
      ],
    );
  }

  Widget _buildSessions() {
    final sessions = _sessions;
    if (sessions == null) return const _Loading();
    if (sessions.isEmpty) {
      return const SettingsPanel(
        children: [
          SettingsTile(
            icon: Icons.tv_off_rounded,
            title: 'Personne ne regarde',
            value: 'Mis à jour toutes les 5 secondes',
          ),
        ],
      );
    }
    return SettingsPanel(
      children: [
        for (final (i, session) in sessions.indexed) ...[
          if (i > 0) const Divider(indent: 16, endIndent: 16),
          _SessionRow(session: session),
        ],
      ],
    );
  }

  Widget _buildActivity() {
    final activity = _activity;
    if (activity == null) {
      return _error == null ? const _Loading() : const SizedBox.shrink();
    }
    if (activity.isEmpty) {
      return const SettingsPanel(
        children: [
          SettingsTile(
            icon: Icons.history_rounded,
            title: 'Rien pour l\'instant',
            value: 'Les connexions et lectures s\'afficheront ici',
          ),
        ],
      );
    }
    final textTheme = Theme.of(context).textTheme;
    final shown = _activityExpanded
        ? activity
        : activity.take(_activityPreview).toList();
    return SettingsPanel(
      children: [
        for (final entry in shown)
          ListTile(
            dense: true,
            leading: Icon(
              entry.isError
                  ? Icons.error_outline_rounded
                  : Icons.circle_outlined,
              size: entry.isError ? 22 : 10,
              color: entry.isError ? AppColors.error : AppColors.grey,
            ),
            title: Text(entry.name, style: textTheme.bodyMedium),
            subtitle: Text(
              [
                if (entry.date != null) timeAgo(entry.date!),
                if (entry.detail != null && entry.detail!.isNotEmpty)
                  entry.detail!,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (shown.length < activity.length)
          TextButton(
            onPressed: () => setState(() => _activityExpanded = true),
            child: const Text('Voir plus'),
          ),
      ],
    );
  }
}

/// Place d'une bibliothèque : nom, « 1,2 To libres sur 4 To » et une barre.
class _StorageRow extends StatelessWidget {
  const _StorageRow({required this.library});

  final LibraryStorage library;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final free = formatFileSize(library.freeBytes) ?? '0';
    final total = formatFileSize(library.totalBytes);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(library.name, style: textTheme.titleSmall)),
              Text(
                total == null ? '$free libres' : '$free libres sur $total',
                style: textTheme.bodySmall?.copyWith(color: AppColors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ProgressLine(value: library.usedFraction, height: 4, rounded: true),
        ],
      ),
    );
  }
}

/// Une lecture en cours : titre, qui et où, avancée, et lecture directe ou
/// conversion.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final ActiveSession session;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final runtime = session.runtime;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                session.paused
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (session.subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 28),
              child: Text(
                session.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '${session.userName} · ${session.device}',
            style: textTheme.bodySmall?.copyWith(color: AppColors.grey),
          ),
          const SizedBox(height: 8),
          ProgressLine(value: session.fraction, height: 4, rounded: true),
          const SizedBox(height: 6),
          Text(
            [
              runtime == null
                  ? formatPosition(session.position)
                  : '${formatPosition(session.position)} / '
                        '${formatPosition(runtime)}',
              session.transcoding
                  ? 'Conversion${session.transcodeDetail == null ? '' : ' : ${session.transcodeDetail}'}'
                  : 'Lecture directe',
            ].join(' · '),
            style: textTheme.bodySmall?.copyWith(color: AppColors.grey),
          ),
        ],
      ),
    );
  }
}

/// Bloc en verre avec une roue, pendant un chargement.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const SettingsPanel(
      children: [
        Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}
