import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_capabilities.dart';
import '../theme/app_theme.dart';

/// Télé : à chaque changement de sélection, la page (et la rangée) défilent
/// pour placer l'élément sélectionné au milieu de l'écran, quel que soit son
/// type (bouton, affiche, ligne…). Sans ça, il peut rester caché sous la
/// barre du haut. À appeler une fois au démarrage.
void followTvFocus() {
  FocusManager.instance.addListener(() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: AppDurations.medium,
      curve: Curves.easeOutCubic,
    );
  });
}

/// Touche « Menu » (☰) de la télécommande : comme OK maintenu (appui long).
class TvMenuIntent extends Intent {
  const TvMenuIntent();
}

/// Touches qui valent « OK » sur une télécommande.
final _okKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

/// Durée d'appui sur OK pour un appui long.
const tvLongPressDelay = Duration(milliseconds: 500);

/// Gestionnaire de sélection où les répétitions de OK sont déjà ignorées.
FocusManager? _okRepeatsIgnoredOn;

/// Télé : tant qu'on garde le doigt sur OK, la télécommande répète « OK ».
/// Ces répétitions sont ignorées partout, sinon elles arrivent sur l'écran
/// qui vient de s'ouvrir (OK maintenu sur une affiche ouvre la fiche, puis
/// lance la lecture ; après un appui long, elles choisiraient la première
/// option du menu). À appeler une fois au démarrage.
void ignoreTvOkRepeats() {
  final manager = FocusManager.instance;
  if (identical(_okRepeatsIgnoredOn, manager)) return;
  _okRepeatsIgnoredOn = manager;
  manager.addEarlyKeyEventHandler(
    (event) => event is KeyRepeatEvent && _okKeys.contains(event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored,
  );
}

/// Rend [child] sélectionnable à la télécommande, sur une télé seulement
/// (ailleurs, [child] est rendu tel quel) : il grossit un peu et prend un
/// contour blanc quand il est sélectionné, la page défile pour le montrer,
/// OK lance [onTap]. OK maintenu 0,5 s ou la touche Menu lancent [onMenu]
/// (l'appui long du téléphone) ; dans ce cas, [onTap] part au relâchement.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.onMenu,
    this.autofocus = false,
    this.radius = AppRadius.poster,
    this.scale = 1.06,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;

  /// Sélectionné à l'arrivée sur l'écran.
  final bool autofocus;

  /// Arrondi du contour (celui de l'élément).
  final double radius;

  /// Grossissement quand il est sélectionné.
  final double scale;
  final FocusNode? focusNode;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  /// OK enfoncé : l'élément rétrécit un peu, comme sur le téléphone.
  bool _pressed = false;

  /// Compte les 0,5 s de l'appui long (actif tant que OK est enfoncé).
  Timer? _holdTimer;

  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  // Le défilement vers l'élément sélectionné : voir [followTvFocus]
  void _onFocusChange(bool focused) {
    if (!focused) _cancelHold();
    setState(() => _focused = focused);
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _pressed = false;
  }

  /// Élément avec appui long : OK court = [onTap] au relâchement,
  /// OK maintenu = [onMenu] sans attendre le relâchement.
  /// Les autres éléments gardent le OK habituel (dès l'appui).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Seulement si c'est lui qui est sélectionné, pas un bouton à l'intérieur
    // (ex. ⓘ d'une ligne d'épisode)
    if (widget.onMenu == null ||
        !_node.hasPrimaryFocus ||
        !_okKeys.contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _holdTimer?.cancel();
      _holdTimer = Timer(tvLongPressDelay, _onLongPress);
      setState(() => _pressed = true);
    } else if (event is KeyUpEvent) {
      // Pas de compteur : OK a été enfoncé ailleurs (écran précédent)
      final shortPress = _holdTimer?.isActive ?? false;
      setState(_cancelHold);
      if (shortPress) widget.onTap?.call();
    }
    return KeyEventResult.handled;
  }

  void _onLongPress() {
    if (!mounted) return;
    setState(_cancelHold);
    widget.onMenu?.call();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!DeviceCapabilities.isTv) return widget.child;
    // Ce Focus voit les touches avant les raccourcis de l'appli (OK = appui)
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: _buildFocusable(),
    );
  }

  Widget _buildFocusable() {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      focusNode: _node,
      onFocusChange: _onFocusChange,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.contextMenu): TvMenuIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
        TvMenuIntent: CallbackAction<TvMenuIntent>(
          onInvoke: (_) {
            widget.onMenu?.call();
            return null;
          },
        ),
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : (_focused ? widget.scale : 1),
        duration: AppDurations.fast,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          // Contour blanc et halo, dessinés par-dessus l'élément
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(
              color: _focused ? AppColors.white : Colors.transparent,
              width: 3,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: [
              if (_focused)
                const BoxShadow(color: AppColors.glow, blurRadius: 24),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Sur une télé, les flèches haut et bas sortent d'un champ de texte (sinon
/// le champ les garde et on ne peut plus aller ailleurs).
class TvTextFieldNavigation extends StatelessWidget {
  const TvTextFieldNavigation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!DeviceCapabilities.isTv) return child;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
          TraversalDirection.up,
          ignoreTextFields: false,
        ),
        SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
          TraversalDirection.down,
          ignoreTextFields: false,
        ),
      },
      child: child,
    );
  }
}

/// Champ de texte à la télécommande (télé seulement ; ailleurs, le champ est
/// rendu tel quel) : le champ se sélectionne aux flèches sans ouvrir le
/// clavier, OK ouvre le clavier, Retour ou « Suivant » le referme.
/// [builder] reçoit le [FocusNode] à donner au champ (null hors télé).
class TvTextField extends StatefulWidget {
  const TvTextField({super.key, required this.builder, this.autofocus = false});

  final Widget Function(FocusNode? focusNode) builder;

  /// Sélectionné à l'arrivée sur l'écran (clavier fermé).
  final bool autofocus;

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  /// Le champ lui-même : hors du parcours aux flèches, il ne prend la main
  /// (et n'ouvre le clavier) qu'après OK.
  final _field = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!DeviceCapabilities.isTv) return widget.builder(null);
    return TvFocusable(
      autofocus: widget.autofocus,
      radius: 16,
      scale: 1.02,
      onTap: _field.requestFocus,
      child: widget.builder(_field),
    );
  }
}

/// Télé : affiche toute l'appli en plus petit ([scale] : 0,75 = un quart de
/// moins). L'appli se croit sur un écran plus grand (1280 × 720 pour une
/// Fire TV), donc elle prend la présentation tablette en paysage (fiches en
/// deux colonnes), puis l'ensemble est réduit pour remplir la télé.
class TvScale extends StatelessWidget {
  const TvScale({super.key, required this.child, this.scale = 0.75});

  final Widget child;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size / scale;
    return MediaQuery(
      data: media.copyWith(
        size: size,
        // Images toujours nettes : même nombre de vrais pixels
        devicePixelRatio: media.devicePixelRatio * scale,
        padding: media.padding / scale,
        viewPadding: media.viewPadding / scale,
        viewInsets: media.viewInsets / scale,
      ),
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(size: size, child: child),
      ),
    );
  }
}
