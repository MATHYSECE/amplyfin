import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/media_item.dart';
import '../models/session.dart';
import '../services/session_store.dart';
import '../theme/app_theme.dart';
import '../widgets/account_sheet.dart';
import '../widgets/connection_pill.dart';
import '../widgets/download_controls.dart';
import '../widgets/library_grid.dart';
import '../widgets/transitions.dart';
import '../widgets/ui.dart';
import 'device_info_screen.dart';
import 'downloads_screen.dart';
import 'home_tab.dart';
import 'login_screen.dart';
import 'movie_screen.dart';
import 'search_tab.dart';
import 'series_screen.dart';

/// Écran principal après la connexion : en-tête (titre, téléchargements,
/// déconnexion), quatre onglets (Accueil, Films, Séries, Recherche) et la
/// barre de navigation en bas. Chaque onglet garde sa position ; un second
/// appui sur l'onglet affiché remonte en haut.
class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    required this.api,
    required this.session,
    this.openDownloads = false,
  });

  final JellyfinApi api;
  final Session session;

  /// Démarrage hors ligne : l'écran des téléchargements s'ouvre tout de
  /// suite par-dessus (le retour mène à l'accueil et à la recherche).
  final bool openDownloads;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _titles = ['Amplyfin', 'Films', 'Séries', 'Recherche'];

  int _tab = 0;

  /// Onglets déjà ouverts (les autres ne sont construits qu'à la demande).
  final Set<int> _visited = {0};

  /// Défilement de chaque onglet.
  final _scrolls = List.generate(4, (_) => ScrollController());
  final _homeKey = GlobalKey<HomeTabState>();

  /// Vrai quand le contenu passe sous l'en-tête : il devient en verre dépoli.
  bool _solid = false;

  /// Vrai quand l'en-tête est caché (on fait défiler vers le bas) : il ne
  /// reste que la bande de la barre d'état. Il revient dès qu'on remonte.
  bool _headerHidden = false;

  /// Dernière position de défilement vue, et chemin parcouru depuis le
  /// dernier changement de sens (évite que l'en-tête clignote).
  double _lastOffset = 0;
  double _travel = 0;

  /// Défilement minimum avant de cacher l'en-tête.
  static const _hideAfter = 120.0;

  @override
  void initState() {
    super.initState();
    for (final scroll in _scrolls) {
      scroll.addListener(_updateHeader);
    }
    if (widget.openDownloads) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showDownloads());
    }
  }

  /// Téléchargements affichés d'emblée (sans animation à l'ouverture,
  /// glissement au retour).
  void _showDownloads() {
    if (!mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: AppDurations.medium,
        pageBuilder: (_, _, _) => DownloadsScreen(
          api: widget.api,
          session: widget.session,
          offlineStart: true,
        ),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final scroll in _scrolls) {
      scroll.dispose();
    }
    super.dispose();
  }

  void _updateHeader() {
    final scroll = _tab < _scrolls.length ? _scrolls[_tab] : null;
    if (scroll == null || !scroll.hasClients) return;
    final offset = scroll.offset;
    final solid = offset > 24;
    final delta = offset - _lastOffset;
    _lastOffset = offset;
    // Même sens qu'avant : on cumule ; changement de sens : on repart de 0
    _travel = (delta > 0) == (_travel > 0) ? _travel + delta : delta;
    var hidden = _headerHidden;
    if (offset < _hideAfter) {
      hidden = false;
    } else if (_travel > 24) {
      hidden = true;
    } else if (_travel < -12) {
      hidden = false;
    }
    if (solid != _solid || hidden != _headerHidden) {
      setState(() {
        _solid = solid;
        _headerHidden = hidden;
      });
    }
  }

  void _select(int tab) {
    if (tab == _tab) {
      // Second appui : retour en haut
      if (tab < _scrolls.length && _scrolls[tab].hasClients) {
        _scrolls[tab].animateTo(
          0,
          duration: AppDurations.emphasized,
          curve: Curves.easeInOutCubicEmphasized,
        );
      }
      return;
    }
    setState(() {
      _tab = tab;
      _visited.add(tab);
      // Nouvel onglet : l'en-tête revient
      _headerHidden = false;
      _travel = 0;
      final scroll = _scrolls[tab];
      _lastOffset = scroll.hasClients ? scroll.offset : 0;
    });
    // Retour sur l'accueil : « Continuer à regarder » à jour
    if (tab == 0) _homeKey.currentState?.refreshContinue();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHeader());
  }

  /// Écran des téléchargements, ouvert en cercle depuis le bouton.
  Future<void> _openDownloads(Offset center) async {
    await Navigator.of(context).push(
      CircleRevealRoute<void>(
        center: center,
        builder: (_) =>
            DownloadsScreen(api: widget.api, session: widget.session),
      ),
    );
    await _homeKey.currentState?.refreshContinue();
  }

  /// Fiche d'un film ou d'une série depuis les onglets Films et Séries.
  Future<void> _open(MediaItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => item.isSeries
            ? SeriesScreen(
                api: widget.api,
                session: widget.session,
                series: item,
              )
            : MovieScreen(
                api: widget.api,
                session: widget.session,
                movie: item,
              ),
      ),
    );
  }

  /// Menu « Compte » : ce que l'appareil sait lire, ou déconnexion.
  Future<void> _openAccount() async {
    final action = await showAccountSheet(context, widget.session);
    if (!mounted) return;
    switch (action) {
      case AccountAction.deviceInfo:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DeviceInfoScreen()),
        );
      case AccountAction.logout:
        // Confirmation : évite de se déconnecter sans le faire exprès
        final confirmed = await showConfirmDialog(
          context,
          title: 'Se déconnecter ?',
          message:
              'Il faudra saisir à nouveau ton mot de passe pour revenir. '
              'Les téléchargements restent sur le téléphone.',
          action: 'Se déconnecter',
          cancel: 'Annuler',
        );
        if (confirmed) await _logout();
      case null:
        break;
    }
  }

  Future<void> _logout() async {
    // On prévient le serveur, mais on se déconnecte même s'il est injoignable
    try {
      await widget.api.logout();
    } on JellyfinException {
      // Rien à faire : le jeton sera de toute façon effacé du téléphone
    }
    await _backToLogin();
  }

  /// Efface la session du téléphone et revient à l'écran de connexion.
  Future<void> _backToLogin() async {
    await SessionStore().clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final wide = AppLayout.isWide(context);
    final headerHeight = padding.top + 64;
    // Place prise par la barre du bas (flottante sur une tablette)
    final barSpace = padding.bottom + (wide ? 92 : 64);

    return Scaffold(
      body: GlowBackground(
        child: Stack(
          children: [
            for (var i = 0; i < _titles.length; i++)
              _TabPage(
                active: i == _tab,
                child: _visited.contains(i)
                    ? _buildTab(i, headerHeight, barSpace)
                    : const SizedBox.shrink(),
              ),
            // Caché : remonte en ne laissant que la bande de la barre d'état
            AnimatedPositioned(
              duration: AppDurations.medium,
              curve: Curves.easeOutCubic,
              top: _headerHidden ? padding.top - headerHeight : 0,
              left: 0,
              right: 0,
              child: _Header(
                title: _titles[_tab],
                solid: _solid || _headerHidden,
                hidden: _headerHidden,
                height: headerHeight,
                gutter: AppLayout.gutter(context),
                wide: wide,
                onDownloads: _openDownloads,
                onAccount: _openAccount,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomBar(index: _tab, wide: wide, onSelect: _select),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(int tab, double headerHeight, double barSpace) {
    LibraryGrid grid(String type, String empty) => LibraryGrid(
      api: widget.api,
      session: widget.session,
      itemType: type,
      emptyMessage: empty,
      topPadding: headerHeight,
      bottomPadding: barSpace,
      controller: _scrolls[tab],
      onOpen: _open,
      onUnauthorized: _backToLogin,
      // Genres en pastilles et bouton « Trier »
      showFilters: true,
    );
    return switch (tab) {
      0 => HomeTab(
        key: _homeKey,
        api: widget.api,
        session: widget.session,
        controller: _scrolls[0],
        headerHeight: headerHeight,
        bottomPadding: barSpace,
        onUnauthorized: _backToLogin,
      ),
      1 => grid('Movie', 'Aucun film trouvé sur ce serveur.'),
      2 => grid('Series', 'Aucune série trouvée sur ce serveur.'),
      _ => SearchTab(
        api: widget.api,
        session: widget.session,
        controller: _scrolls[3],
        headerHeight: headerHeight,
        bottomPadding: barSpace,
        active: _tab == 3,
      ),
    };
  }
}

/// Un onglet : visible (fondu) quand il est choisi ; sinon caché, sans
/// réagir aux appuis ni aux animations d'affiche.
class _TabPage extends StatelessWidget {
  const _TabPage({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !active,
      child: HeroMode(
        enabled: active,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: AppDurations.medium,
          curve: Curves.easeOut,
          child: AnimatedSlide(
            offset: active ? Offset.zero : const Offset(0, 0.015),
            duration: AppDurations.medium,
            curve: Curves.easeOutCubic,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// En-tête : transparent en haut de page, en verre dépoli dès qu'on fait
/// défiler. Titre de l'onglet, téléchargements et déconnexion.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.solid,
    required this.hidden,
    required this.height,
    required this.gutter,
    required this.wide,
    required this.onDownloads,
    required this.onAccount,
  });

  final String title;
  final bool solid;

  /// Vrai quand l'en-tête est remonté : son contenu s'efface.
  final bool hidden;
  final double height;
  final double gutter;

  /// Tablette : la pastille de connexion affiche aussi son mot.
  final bool wide;
  final ValueChanged<Offset> onDownloads;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: solid ? 1 : 0),
      duration: AppDurations.medium,
      builder: (context, t, child) => ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18 * t, sigmaY: 18 * t),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: Color.lerp(Colors.transparent, AppColors.scrim70, t),
              border: Border(
                bottom: BorderSide(
                  color: Color.lerp(
                    Colors.transparent,
                    AppColors.glassBorder,
                    t,
                  )!,
                ),
              ),
            ),
            padding: EdgeInsets.fromLTRB(gutter, topInset + 8, gutter, 10),
            child: IgnorePointer(
              ignoring: hidden,
              child: AnimatedOpacity(
                opacity: hidden ? 0 : 1,
                duration: AppDurations.fast,
                child: child,
              ),
            ),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: AppDurations.medium,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, ?current],
              ),
              child: Text(
                title,
                key: ValueKey(title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ),
          // État de la connexion (seulement s'il y a quelque chose à dire)
          ConnectionPill(showLabel: wide),
          DownloadsButton(onPressed: onDownloads),
          const SizedBox(width: 10),
          GlassCircleButton(
            icon: Icons.person_rounded,
            tooltip: 'Compte',
            onPressed: onAccount,
          ),
        ],
      ),
    );
  }
}

/// Barre de navigation : pastille blanche qui glisse sous l'onglet choisi.
/// Sur une tablette, une pilule flottante en bas au centre.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.wide,
    required this.onSelect,
  });

  static const _items = [
    (Icons.home_rounded, 'Accueil'),
    (Icons.movie_outlined, 'Films'),
    (Icons.tv_rounded, 'Séries'),
    (Icons.search_rounded, 'Recherche'),
  ];

  final int index;
  final bool wide;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / _items.length;
        // Téléphone : petite pastille sous l'icône ; tablette : tout l'onglet
        final pillWidth = wide ? width - 8 : 56.0;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: AppDurations.emphasized,
              curve: Curves.easeInOutCubicEmphasized,
              left: index * width + (width - pillWidth) / 2,
              top: wide ? 4 : 6,
              width: pillWidth,
              height: wide ? 52 : 32,
              child: const DecoratedBox(
                decoration: ShapeDecoration(
                  color: AppColors.white,
                  shape: StadiumBorder(),
                ),
              ),
            ),
            // Toute la hauteur de la barre : sur une tablette, les onglets
            // sont centrés sur la pastille
            Positioned.fill(
              child: Row(
                children: [
                  for (final (i, (icon, label)) in _items.indexed)
                    Expanded(
                      child: _BarItem(
                        icon: icon,
                        label: label,
                        selected: i == index,
                        wide: wide,
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (wide) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset + 22),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 480,
                height: 60,
                decoration: ShapeDecoration(
                  color: AppColors.scrim70,
                  shape: const StadiumBorder(
                    side: BorderSide(color: AppColors.glassBorder),
                  ),
                ),
                child: bar,
              ),
            ),
          ),
        ),
      );
    }
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64 + bottomInset,
          padding: EdgeInsets.only(bottom: bottomInset),
          decoration: const BoxDecoration(
            color: AppColors.scrim70,
            border: Border(top: BorderSide(color: AppColors.glassBorder)),
          ),
          child: bar,
        ),
      ),
    );
  }
}

/// Un onglet de la barre : icône et nom, en noir sur la pastille quand il
/// est choisi.
class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.wide,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? AppColors.black : AppColors.grey;
    // Téléphone : le nom reste sous la pastille, en blanc
    final labelColor = selected
        ? (wide ? AppColors.black : AppColors.white)
        : AppColors.grey;
    final style = Theme.of(context).textTheme.labelSmall;
    final iconWidget = TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: iconColor),
      duration: AppDurations.medium,
      builder: (context, color, _) => AnimatedScale(
        scale: selected ? 1.06 : 1,
        duration: AppDurations.medium,
        curve: Curves.easeOutBack,
        child: Icon(icon, size: 23, color: color),
      ),
    );
    final text = AnimatedDefaultTextStyle(
      duration: AppDurations.medium,
      style: (style ?? const TextStyle()).copyWith(
        color: labelColor,
        fontSize: wide ? 13 : 11,
      ),
      child: Text(label),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: wide
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [iconWidget, const SizedBox(width: 8), text],
              )
            : Column(
                children: [
                  const SizedBox(height: 10),
                  iconWidget,
                  const SizedBox(height: 7),
                  text,
                ],
              ),
      ),
    );
  }
}
