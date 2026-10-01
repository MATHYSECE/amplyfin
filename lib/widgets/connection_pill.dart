import 'package:flutter/material.dart';

import '../services/connection_monitor.dart';
import '../theme/app_theme.dart';

/// Pastille d'état de la connexion, à côté du bouton Téléchargements :
/// nuage barré hors ligne, petite roue pendant la reconnexion, nuage coché
/// quelques secondes au retour ; rien quand tout va bien. Un appui ouvre
/// une bulle qui explique l'état. [showLabel] : le mot à côté de l'icône
/// (tablette).
class ConnectionPill extends StatefulWidget {
  const ConnectionPill({super.key, this.showLabel = false});

  final bool showLabel;

  @override
  State<ConnectionPill> createState() => _ConnectionPillState();
}

/// Ce que montre la pastille.
enum _PillState { hidden, offline, checking, reconnected }

class _ConnectionPillState extends State<ConnectionPill> {
  final _bubble = OverlayPortalController();
  final _link = LayerLink();
  final _connection = ConnectionMonitor.instance;

  _PillState get _state {
    if (!_connection.online) {
      return _connection.checking ? _PillState.checking : _PillState.offline;
    }
    return _connection.justReconnected
        ? _PillState.reconnected
        : _PillState.hidden;
  }

  @override
  void initState() {
    super.initState();
    _connection.addListener(_onChange);
  }

  @override
  void dispose() {
    _connection.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    // Plus rien à dire : la bulle se ferme avec la pastille
    if (_state == _PillState.hidden && _bubble.isShowing) _bubble.hide();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final (icon, label) = switch (state) {
      _PillState.offline => (Icons.cloud_off_rounded, 'Hors ligne'),
      _PillState.checking => (null, 'Connexion…'),
      _PillState.reconnected => (Icons.cloud_done_outlined, 'En ligne'),
      _PillState.hidden => (null, ''),
    };
    final Widget pill = state == _PillState.hidden
        ? const SizedBox.shrink(key: ValueKey('hidden'))
        : Padding(
            key: const ValueKey('pill'),
            padding: const EdgeInsets.only(right: 10),
            child: CompositedTransformTarget(
              link: _link,
              child: Tooltip(
                message: label,
                child: Material(
                  color: AppColors.scrim35,
                  shape: const StadiumBorder(
                    side: BorderSide(color: AppColors.glassBorder),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _bubble.toggle,
                    child: Container(
                      height: 44,
                      constraints: const BoxConstraints(minWidth: 44),
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.showLabel ? 14 : 0,
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // L'icône change avec un petit rebond
                          AnimatedSwitcher(
                            duration: AppDurations.medium,
                            switchInCurve: Curves.easeOutBack,
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(scale: animation, child: child),
                            child: icon == null
                                ? const SizedBox.square(
                                    key: ValueKey('spinner'),
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(icon, key: ValueKey(icon), size: 20),
                          ),
                          if (widget.showLabel) ...[
                            const SizedBox(width: 8),
                            Text(
                              label,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

    return OverlayPortal(
      controller: _bubble,
      overlayChildBuilder: (context) => _Bubble(
        link: _link,
        state: state,
        onClose: _bubble.hide,
        onRetry: () {
          _connection.check();
        },
      ),
      // La pastille apparaît et disparaît en douceur
      child: AnimatedSize(
        duration: AppDurations.medium,
        curve: Curves.easeOutCubic,
        child: AnimatedSwitcher(
          duration: AppDurations.medium,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: pill,
        ),
      ),
    );
  }
}

/// Bulle sous la pastille : ce qui se passe, en clair. Un appui ailleurs la
/// ferme.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.link,
    required this.state,
    required this.onClose,
    required this.onRetry,
  });

  final LayerLink link;
  final _PillState state;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (title, message) = switch (state) {
      _PillState.offline || _PillState.hidden => (
        'Hors ligne',
        'Le serveur Jellyfin ne répond pas : Wi-Fi et données coupés, ou '
            'serveur éteint. Tes téléchargements restent disponibles, et '
            'Amplyfin se reconnecte tout seul dès que le réseau revient.',
      ),
      _PillState.checking => (
        'Connexion en cours…',
        'Le réseau est revenu : Amplyfin vérifie que le serveur répond.',
      ),
      _PillState.reconnected => (
        'De nouveau en ligne',
        'Le serveur répond. L\'accueil se met à jour, et ce que tu as '
            'regardé hors ligne lui a été envoyé.',
      ),
    };
    final screenWidth = MediaQuery.sizeOf(context).width;
    final width = screenWidth < 360 ? screenWidth - 32 : 300.0;
    return Stack(
      children: [
        // Appui ailleurs : la bulle se ferme
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onClose,
          ),
        ),
        CompositedTransformFollower(
          link: link,
          // Sous la pastille, alignée sur son bord droit
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(-10, 10),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: AppDurations.medium,
            curve: Curves.easeOutBack,
            builder: (context, t, child) => Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.9 + 0.1 * t,
                alignment: Alignment.topRight,
                child: child,
              ),
            ),
            child: SizedBox(
              width: width,
              child: Material(
                color: AppColors.surface2,
                elevation: 12,
                shadowColor: AppColors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  side: const BorderSide(color: AppColors.glassBorder),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textSoft,
                          height: 1.45,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: state == _PillState.offline
                            ? TextButton(
                                onPressed: onRetry,
                                child: const Text('Réessayer maintenant'),
                              )
                            : const SizedBox(height: 8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
