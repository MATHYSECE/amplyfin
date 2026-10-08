import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/session.dart';
import '../services/connection_monitor.dart';
import '../services/download_manager.dart';
import '../services/profile_switch.dart';
import '../services/session_store.dart';
import '../theme/app_theme.dart';
import '../widgets/tv_focus.dart';
import '../widgets/ui.dart';
import 'login_screen.dart';
import 'main_screen.dart';

/// Ouvre le profil [session] : il devient le profil en cours, son jeton est
/// vérifié, puis on renvoie l'écran à afficher (accueil, ou connexion si le
/// serveur ne reconnaît plus son jeton).
Future<Widget> openProfile(Session session) async {
  final store = SessionStore();
  await store.select(session);
  final api = JellyfinApi(
    serverUrl: session.serverUrl,
    deviceId: await store.deviceId(),
    token: session.accessToken,
  );

  // Le jeton est-il toujours accepté par le serveur ? (4 s au plus)
  switch (await checkServer(api)) {
    case ServerStatus.unauthorized:
      // Jeton révoqué (ex. déconnecté depuis le tableau de bord Jellyfin)
      await store.remove(session);
      return LoginScreen(
        userName: session.userName,
        message:
            'La connexion de ${session.userName} a expiré : '
            'saisis à nouveau son mot de passe.',
      );
    case ServerStatus.reachable:
      beginProfile(api, session.userId, online: true);
      unawaited(_refreshProfile(store, api, session));
      return MainScreen(api: api, session: session);
    case ServerStatus.unreachable:
      // Hors ligne : les téléchargements (s'il y en a) s'ouvrent par-dessus
      // l'écran principal
      beginProfile(api, session.userId, online: false);
      final downloads = DownloadManager.instance;
      await downloads.init();
      final hasDownloads = downloads.states.values.any(
        (s) => s.phase == DownloadPhase.complete,
      );
      return MainScreen(
        api: api,
        session: session,
        openDownloads: hasDownloads,
      );
  }
}

/// Relit le nom et la photo de la personne sur le serveur (s'ils ont changé
/// dans Jellyfin, « Qui regarde ? » les montre la fois suivante).
Future<void> _refreshProfile(
  SessionStore store,
  JellyfinApi api,
  Session session,
) async {
  try {
    final info = await api.getProfileInfo();
    if (info.name == session.userName && info.imageTag == session.imageTag) {
      return;
    }
    await store.save(
      session.withProfile(
        userName: info.name.isEmpty ? session.userName : info.name,
        imageTag: info.imageTag,
      ),
    );
  } on JellyfinException {
    // Pas grave : on réessaiera à la prochaine ouverture
  }
}

/// Retire le profil [session] de l'appareil. Le serveur est prévenu d'abord
/// (son jeton ne servira plus) ; s'il ne répond pas, le profil est retiré
/// quand même.
Future<void> removeProfile(Session session, {required String deviceId}) async {
  final api = JellyfinApi(
    serverUrl: session.serverUrl,
    deviceId: deviceId,
    token: session.accessToken,
  );
  try {
    await api.logout().timeout(const Duration(seconds: 4));
  } on JellyfinException {
    // Jeton déjà refusé ou serveur injoignable : rien à faire
  } on TimeoutException {
    // Serveur trop lent : tant pis
  }
  await SessionStore().remove(session);
}

/// Remplace tous les écrans par [screen], en fondu.
void showOnly(BuildContext context, Widget screen) {
  Navigator.of(context).pushAndRemoveUntil(
    PageRouteBuilder<void>(
      transitionDuration: AppDurations.medium,
      pageBuilder: (_, _, _) => screen,
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
    (_) => false,
  );
}

/// « Qui regarde ? » : une vignette par personne connectée sur l'appareil
/// (photo Jellyfin ou initiales), puis « Ajouter un profil ».
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  final _store = SessionStore();

  List<Session>? _profiles;

  /// Dernier profil utilisé (sélectionné à l'arrivée sur une télé).
  String? _lastUserId;
  String? _deviceId;

  /// Profil en cours d'ouverture (roue sur sa vignette).
  Session? _opening;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profiles = await _store.profiles();
    final last = await _store.load();
    final deviceId = await _store.deviceId();
    if (!mounted) return;
    // Plus aucun profil : écran de connexion
    if (profiles.isEmpty) {
      showOnly(context, const LoginScreen());
      return;
    }
    setState(() {
      _profiles = profiles;
      _lastUserId = last?.userId;
      _deviceId = deviceId;
    });
  }

  Future<void> _open(Session session) async {
    if (_opening != null) return;
    setState(() => _opening = session);
    final screen = await openProfile(session);
    if (!mounted) return;
    showOnly(context, screen);
  }

  /// Appui long sur une vignette : « Retirer ce profil » (après
  /// confirmation).
  Future<void> _showOptions(Session session) async {
    final remove = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                session.userName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined),
              title: const Text('Retirer ce profil'),
              subtitle: const Text('De cet appareil seulement'),
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (remove != true || !mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Retirer ce profil ?',
      message:
          'Le profil de ${session.userName} sera retiré de cet appareil. '
          'Il faudra saisir à nouveau son mot de passe pour le remettre.',
      action: 'Retirer',
    );
    if (!confirmed) return;
    await removeProfile(session, deviceId: await _store.deviceId());
    await _load();
  }

  void _addProfile() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: GlowBackground(
        child: SafeArea(
          child: profiles == null
              ? const SizedBox.shrink()
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          'Qui regarde ?',
                          textAlign: TextAlign.center,
                          style: textTheme.displaySmall,
                        ),
                        const SizedBox(height: 40),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 28,
                          runSpacing: 28,
                          children: [
                            for (final session in profiles)
                              _ProfileTile(
                                label: session.userName,
                                autofocus: session.userId == _lastUserId,
                                loading: identical(session, _opening),
                                onTap: () => _open(session),
                                onLongPress: () => _showOptions(session),
                                avatar: ProfileAvatar(
                                  session: session,
                                  deviceId: _deviceId,
                                ),
                              ),
                            _ProfileTile(
                              label: 'Ajouter un profil',
                              onTap: _addProfile,
                              avatar: const _AddAvatar(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Taille des vignettes de « Qui regarde ? ».
const _avatarSize = 112.0;

/// Une vignette : le rond (photo, initiales ou « + ») et le prénom dessous.
class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.label,
    required this.avatar,
    required this.onTap,
    this.onLongPress,
    this.autofocus = false,
    this.loading = false,
  });

  final String label;
  final Widget avatar;
  final VoidCallback onTap;

  /// Appui long (télé : OK maintenu) : options du profil.
  final VoidCallback? onLongPress;
  final bool autofocus;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    // Toute la vignette se touche (rond et prénom)
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: _avatarSize + 24,
        child: Column(
          children: [
            // Télé : sélection ronde à la télécommande
            TvFocusable(
              autofocus: autofocus,
              onTap: onTap,
              onMenu: onLongPress,
              radius: _avatarSize / 2,
              scale: 1.08,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  avatar,
                  if (loading)
                    const SizedBox.square(
                      dimension: 36,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Rond d'un profil : sa photo Jellyfin, sinon ses initiales.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.session,
    required this.deviceId,
    this.size = _avatarSize,
  });

  final Session session;

  /// Identifiant de l'appareil (pour charger la photo avec son jeton).
  final String? deviceId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = _Initials(name: session.userName, size: size);
    final tag = session.imageTag;
    final device = deviceId;
    if (tag == null || device == null) return initials;
    // La photo demande d'être connecté : on l'envoie avec le jeton du profil
    final api = JellyfinApi(
      serverUrl: session.serverUrl,
      deviceId: device,
      token: session.accessToken,
    );
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: api.userImageUrl(session.userId, tag),
        httpHeaders: api.streamHeaders,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => initials,
        errorWidget: (_, _, _) => initials,
      ),
    );
  }
}

/// Initiales sur un rond en dégradé gris (pas de photo).
class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface3, AppColors.surface1],
        ),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Text(
        initialsOf(name),
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontSize: size * 0.34, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Rond « + » de « Ajouter un profil ».
class _AddAvatar extends StatelessWidget {
  const _AddAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.glass,
        border: Border.all(color: AppColors.outlineStrong),
      ),
      child: Icon(
        Icons.add_rounded,
        size: _avatarSize * 0.4,
        color: AppColors.grey,
      ),
    );
  }
}
