import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/languages.dart';
import '../models/session.dart';
import '../models/subtitle_size.dart';
import '../models/user_settings.dart';
import '../services/connection_monitor.dart';
import '../services/download_manager.dart';
import '../services/player_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/track_picker.dart';
import '../widgets/ui.dart';
import 'admin_screen.dart';
import 'device_info_screen.dart';

/// Page « Paramètres » (menu Compte) : langues préférées du compte, taille
/// des sous-titres, téléchargements en données mobiles, ce que l'appareil
/// sait lire, administration du serveur (administrateurs) et « À propos ».
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api, required this.session});

  final JellyfinApi api;
  final Session session;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _playerPreferences = PlayerPreferences();

  /// Réglages du compte (null tant qu'ils chargent, ou sans serveur).
  UserSettings? _settings;
  String? _error;
  SubtitleSize _subtitleSize = SubtitleSize.medium;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadSubtitleSize();
  }

  Future<void> _loadSettings() async {
    setState(() => _error = null);
    try {
      final settings = await widget.api.getUserSettings();
      if (mounted) setState(() => _settings = settings);
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadSubtitleSize() async {
    final size = await _playerPreferences.loadSubtitleSize();
    if (mounted) setState(() => _subtitleSize = size);
  }

  /// Enregistre les langues sur le serveur. En cas d'échec, l'ancien
  /// réglage revient et un message s'affiche.
  Future<void> _save(UserSettings updated) async {
    final previous = _settings;
    setState(() => _settings = updated);
    try {
      await widget.api.saveUserSettings(
        userId: widget.session.userId,
        settings: updated,
      );
    } on JellyfinException catch (e) {
      if (!mounted) return;
      setState(() => _settings = previous);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _chooseAudio(UserSettings settings) async {
    final chosen = await showPicker<String?>(
      context,
      title: 'Audio préféré',
      options: [
        const PickerOption(
          null,
          'Langue d\'origine',
          description: 'La piste principale de chaque fichier',
        ),
        for (final code in knownLanguages)
          PickerOption(code, languageName(code)),
      ],
      selected: settings.audioLanguage,
    );
    if (chosen == null || chosen.value == settings.audioLanguage) return;
    await _save(
      settings.copyWith(
        audioLanguage: chosen.value,
        clearAudio: chosen.value == null,
      ),
    );
  }

  Future<void> _chooseSubtitleLanguage(UserSettings settings) async {
    final chosen = await showPicker<String?>(
      context,
      title: 'Sous-titres préférés',
      options: [
        const PickerOption(null, 'Aucune préférence'),
        for (final code in knownLanguages)
          PickerOption(code, languageName(code)),
      ],
      selected: settings.subtitleLanguage,
    );
    if (chosen == null || chosen.value == settings.subtitleLanguage) return;
    await _save(
      settings.copyWith(
        subtitleLanguage: chosen.value,
        clearSubtitle: chosen.value == null,
      ),
    );
  }

  Future<void> _chooseSubtitleMode(UserSettings settings) async {
    final chosen = await showPicker(
      context,
      title: 'Quand afficher les sous-titres',
      options: [
        for (final mode in SubtitleMode.values)
          PickerOption(mode, mode.label, description: mode.description),
      ],
      selected: settings.subtitleMode,
    );
    if (chosen == null || chosen.value == settings.subtitleMode) return;
    await _save(settings.copyWith(subtitleMode: chosen.value));
  }

  Future<void> _chooseSubtitleSize() async {
    final chosen = await showPicker(
      context,
      title: 'Taille des sous-titres',
      options: [
        for (final size in SubtitleSize.values) PickerOption(size, size.label),
      ],
      selected: _subtitleSize,
    );
    if (chosen == null || !mounted) return;
    setState(() => _subtitleSize = chosen.value);
    await _playerPreferences.saveSubtitleSize(chosen.value);
  }

  void _push(Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final side = AppLayout.isWide(context)
        ? AppLayout.centeredGutter(context)
        : 20.0;
    final settings = _settings;

    return Scaffold(
      body: GlowBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            side,
            padding.top + 8,
            side,
            padding.bottom + 32,
          ),
          children: [
            ScreenTitleRow(title: 'Paramètres'),
            const SizedBox(height: 20),
            const SettingsSectionTitle('Langues préférées'),
            if (settings != null)
              _buildLanguages(settings)
            else if (_error != null)
              SettingsPanel(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_off_rounded),
                    title: const Text('Disponible avec une connexion'),
                    subtitle: Text(_error!),
                    trailing: TextButton(
                      onPressed: _loadSettings,
                      child: const Text('Réessayer'),
                    ),
                  ),
                ],
              )
            else
              const SettingsPanel(
                children: [
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              ),
            const SettingsNote(
              'Enregistrées sur ton compte Jellyfin : elles valent aussi pour '
              'ses autres applis. Le choix fait pour une série passe avant.',
            ),
            const SizedBox(height: 22),
            const SettingsSectionTitle('Lecture'),
            SettingsPanel(
              children: [
                SettingsTile(
                  icon: Icons.format_size_rounded,
                  title: 'Taille des sous-titres',
                  value: _subtitleSize.label,
                  onTap: _chooseSubtitleSize,
                ),
              ],
            ),
            const SizedBox(height: 22),
            const SettingsSectionTitle('Téléchargements'),
            ListenableBuilder(
              listenable: DownloadManager.instance,
              builder: (context, _) => SettingsPanel(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.signal_cellular_alt_rounded),
                    title: const Text('Utiliser les données mobiles'),
                    subtitle: const Text(
                      'Sinon, en Wi-Fi uniquement. Un film pèse souvent '
                      'plusieurs Go : attention à ton forfait.',
                    ),
                    value: DownloadManager.instance.allowsMobileData,
                    onChanged: DownloadManager.instance.setMobileData,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const SettingsSectionTitle('Appareil'),
            SettingsPanel(
              children: [
                SettingsTile(
                  icon: Icons.memory_rounded,
                  title: 'Ce que ton appareil sait lire',
                  value: 'Formats vidéo et son, 4K, HDR',
                  onTap: () => _push(const DeviceInfoScreen()),
                ),
              ],
            ),
            if (settings?.isAdmin ?? false) ...[
              const SizedBox(height: 22),
              const SettingsSectionTitle('Administration'),
              SettingsPanel(
                children: [
                  SettingsTile(
                    icon: Icons.dns_rounded,
                    title: 'Administration du serveur',
                    value: 'Infos, lectures en cours, bibliothèque, journal',
                    onTap: () => _push(AdminScreen(api: widget.api)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            const SettingsSectionTitle('À propos'),
            SettingsPanel(
              children: [
                const SettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: 'Amplyfin',
                  value: 'Version ${JellyfinApi.clientVersion}',
                ),
                const Divider(indent: 16, endIndent: 16),
                SettingsTile(
                  icon: Icons.account_circle_outlined,
                  title: widget.session.userName,
                  value: widget.session.serverUrl,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguages(UserSettings settings) {
    return ListenableBuilder(
      listenable: ConnectionMonitor.instance,
      builder: (context, _) {
        // Hors ligne : affichés, mais pas modifiables
        final online = ConnectionMonitor.instance.online;
        VoidCallback? when(VoidCallback action) => online ? action : null;
        return SettingsPanel(
          children: [
            SettingsTile(
              icon: Icons.volume_up_outlined,
              title: 'Audio',
              value: settings.audioLanguage == null
                  ? 'Langue d\'origine'
                  : languageName(settings.audioLanguage),
              onTap: when(() => _chooseAudio(settings)),
            ),
            const Divider(indent: 16, endIndent: 16),
            SettingsTile(
              icon: Icons.subtitles_outlined,
              title: 'Sous-titres',
              value: settings.subtitleLanguage == null
                  ? 'Aucune préférence'
                  : languageName(settings.subtitleLanguage),
              onTap: when(() => _chooseSubtitleLanguage(settings)),
            ),
            const Divider(indent: 16, endIndent: 16),
            SettingsTile(
              icon: Icons.closed_caption_outlined,
              title: 'Quand afficher les sous-titres',
              value:
                  '${settings.subtitleMode.label} · '
                  '${settings.subtitleMode.description}',
              onTap: when(() => _chooseSubtitleMode(settings)),
            ),
          ],
        );
      },
    );
  }
}

/// En-tête d'une page : bouton retour et titre.
class ScreenTitleRow extends StatelessWidget {
  const ScreenTitleRow({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GlassCircleButton(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
      ],
    );
  }
}

/// Titre d'une section, en gris.
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: AppColors.grey),
      ),
    );
  }
}

/// Bloc en verre qui regroupe des lignes de réglage.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(child: Column(children: children));
  }
}

/// Une ligne de réglage : icône, nom, valeur actuelle en dessous, et une
/// flèche si on peut la toucher.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right_rounded, color: AppColors.greyDark),
      onTap: onTap,
    );
  }
}

/// Petite explication sous un bloc.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AppColors.grey),
      ),
    );
  }
}
