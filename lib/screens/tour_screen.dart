import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tour.dart';
import '../services/device_capabilities.dart';
import '../services/tour_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Façon d'utiliser cet appareil (pour adapter la visite et l'astuce).
TourDevice currentTourDevice() => DeviceCapabilities.isTv
    ? TourDevice.tv
    : DeviceCapabilities.isDesktop
    ? TourDevice.desktop
    : TourDevice.touch;

/// Visite guidée : quelques pages pour découvrir l'appli, adaptées à
/// l'appareil. « Passer » ou « Commencer » la ferment et la marquent vue
/// pour ce profil. On avance en glissant, avec les flèches (clavier,
/// télécommande) ou avec « Suivant ».
class TourScreen extends StatefulWidget {
  const TourScreen({super.key, this.device});

  /// Appareil (par défaut celui-ci ; précisé dans les tests).
  final TourDevice? device;

  /// Vrai pendant que la visite est ouverte : l'écran principal, dessous,
  /// est figé (télé : sinon il prend la sélection quand l'accueil finit de
  /// charger, et les flèches bougent dans un écran invisible).
  static final isOpen = ValueNotifier<bool>(false);

  /// Ouvre la visite par-dessus l'écran actuel.
  static Future<void> show(BuildContext context) async {
    isOpen.value = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const TourScreen(),
        ),
      );
    } finally {
      isOpen.value = false;
    }
  }

  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> {
  late final TourDevice _device = widget.device ?? currentTourDevice();
  late final List<TourPage> _pages = tourPages(_device);
  final _controller = PageController();
  int _index = 0;

  /// « Passer » et le bouton du bas : les seuls éléments sélectionnables.
  final _skipFocus = FocusNode(debugLabel: 'Passer');
  final _nextFocus = FocusNode(debugLabel: 'Suivant');

  bool get _last => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    _skipFocus.dispose();
    _nextFocus.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= _pages.length) return;
    _controller.animateToPage(
      index,
      duration: AppDurations.medium,
      curve: Curves.easeOutCubic,
    );
  }

  /// Suivant, ou fin de la visite sur la dernière page.
  void _next() => _last ? _finish() : _goTo(_index + 1);

  /// Visite terminée ou passée : vue pour ce profil.
  Future<void> _finish() async {
    await TourPreferences().markTourSeen();
    if (mounted) Navigator.of(context).pop();
  }

  /// Les quatre flèches (clavier, télécommande) sont gérées ici, pour
  /// que la sélection ne parte jamais dans l'écran caché dessous :
  /// gauche / droite = page précédente / suivante, haut = « Passer »,
  /// bas = le bouton du bas.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _goTo(_index + 1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _goTo(_index - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      // Dernière page : pas de « Passer », on reste sur « Commencer »
      if (!_last) _skipFocus.requestFocus();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _nextFocus.requestFocus();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Nouvelle page : sur la dernière, « Passer » disparaît ; s'il était
  /// sélectionné, la sélection passe sur « Commencer ».
  void _onPageChanged(int index) {
    setState(() => _index = index);
    if (_last && _skipFocus.hasFocus) _nextFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final padding = MediaQuery.paddingOf(context);
    return PopScope(
      // Retour (télé, Échap) : comme « Passer »
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: GlowBackground(
          child: Focus(
            onKeyEvent: _onKey,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                padding.top + 16,
                24,
                padding.bottom + 24,
              ),
              child: Column(
                children: [
                  // Hauteur fixe : rien ne bouge quand « Passer » disparaît
                  SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        Text(
                          '${_index + 1} / ${_pages.length}',
                          style: textTheme.labelLarge?.copyWith(
                            color: AppColors.grey,
                          ),
                        ),
                        const Spacer(),
                        if (!_last)
                          OutlinedButton(
                            focusNode: _skipFocus,
                            onPressed: _finish,
                            child: const Text('Passer'),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _pages.length,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, index) =>
                          _TourPageView(page: _pages[index], device: _device),
                    ),
                  ),
                  _Dots(count: _pages.length, index: _index),
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        // Télé : sélectionné d'emblée, OK suffit
                        focusNode: _nextFocus,
                        autofocus: true,
                        onPressed: _next,
                        child: Text(_last ? 'Commencer' : 'Suivant'),
                      ),
                    ),
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

/// Une page : illustration, titre et texte (côte à côte sur grand écran).
class _TourPageView extends StatelessWidget {
  const _TourPageView({required this.page, required this.device});

  final TourPage page;
  final TourDevice device;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scene = _TourIllustration(scene: page.scene, device: device);
    final words = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          page.title,
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          page.text,
          style: textTheme.bodyLarge?.copyWith(
            color: AppColors.textSoft,
            height: 1.5,
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppLayout.wideWidth;
        final content = wide
            ? Row(
                children: [
                  Expanded(child: Center(child: scene)),
                  const SizedBox(width: 48),
                  Expanded(child: words),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [scene, const SizedBox(height: 28), words],
              );
        return Center(
          child: SingleChildScrollView(
            // Le halo de l'illustration dépasse : pas découpé en carré
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1000 : 480),
              child: content,
            ),
          ),
        );
      },
    );
  }
}

/// Points de progression : la page en cours est un trait allongé.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Page ${index + 1} sur $count',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: AppDurations.fast,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == index ? 22 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index ? AppColors.white : AppColors.track,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
        ],
      ),
    );
  }
}

/// Carte translucide qui porte une illustration.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: child,
    );
  }
}

/// Mention du lecteur (ORIGINAL, SON CONVERTI…).
class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 124,
      padding: const EdgeInsets.symmetric(vertical: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.outlineStrong),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.8),
      ),
    );
  }
}

/// Fausse affiche (dégradé gris), avec ou sans barre de progression.
class _Poster extends StatelessWidget {
  const _Poster({required this.shade, this.progress, this.width = 84});

  final double shade;
  final double? progress;
  final double width;

  @override
  Widget build(BuildContext context) {
    final light = Color.lerp(AppColors.surface3, AppColors.grey, shade)!;
    return Container(
      width: width,
      height: width * 1.5,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.poster),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, AppColors.surface1],
        ),
      ),
      alignment: Alignment.bottomLeft,
      child: progress == null ? null : ProgressLine(value: progress!),
    );
  }
}

/// Ligne « icône + texte » d'un faux menu.
class _MenuLine extends StatelessWidget {
  const _MenuLine(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Une commande (touche, geste) et son effet.
class _KeyLine extends StatelessWidget {
  const _KeyLine(this.entry);

  final TourKey entry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outlineStrong),
            ),
            child: Text(
              entry.key,
              textAlign: TextAlign.center,
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                entry.action,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSoft,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Illustration d'une page, dessinée avec les couleurs de l'appli.
class _TourIllustration extends StatelessWidget {
  const _TourIllustration({required this.scene, required this.device});

  final TourScene scene;
  final TourDevice device;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final small = textTheme.bodySmall?.copyWith(
      color: AppColors.grey,
      fontWeight: FontWeight.w600,
    );
    switch (scene) {
      case TourScene.welcome:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.glassStrong,
                border: Border.all(color: AppColors.glassBorder),
                boxShadow: const [
                  BoxShadow(color: AppColors.glow, blurRadius: 60),
                ],
              ),
              child: const Icon(Icons.play_arrow_rounded, size: 56),
            ),
            const SizedBox(height: 24),
            for (final (label, meaning) in const [
              ('ORIGINAL', 'Le fichier tel quel'),
              ('SON CONVERTI', 'Image d\'origine, seul le son est adapté'),
              ('CONVERTI', 'Le serveur adapte la vidéo'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    _Badge(label),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        meaning,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      case TourScene.resume:
        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Continuer à regarder',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  _Poster(shade: 0.6, progress: 0.62),
                  SizedBox(width: 10),
                  _Poster(shade: 0.9, progress: 0.3),
                  SizedBox(width: 10),
                  _Poster(shade: 0.4),
                ],
              ),
              const Divider(height: 28),
              if (device != TourDevice.tv)
                const _MenuLine(Icons.download_rounded, 'Télécharger'),
              const _MenuLine(Icons.check_rounded, 'Marquer comme vu'),
              const _MenuLine(
                Icons.remove_circle_outline_rounded,
                'Retirer (en gardant ou non sa progression)',
              ),
            ],
          ),
        );
      case TourScene.details:
        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: const Text('Audio : Français'),
                    backgroundColor: AppColors.white,
                    labelStyle: textTheme.labelMedium?.copyWith(
                      color: AppColors.black,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Chip(label: Text('Sous-titres : Aucun')),
                ],
              ),
              const SizedBox(height: 14),
              for (final (title, info, watched) in const [
                ('3. Le Pont', '52 min · 2,8 Go · 4K · HEVC · HDR10', false),
                ('4. La Tempête', '48 min · 2,5 Go · 4K · HEVC · HDR10', true),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 104,
                        height: 58,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: AppColors.surface3,
                          borderRadius: BorderRadius.circular(AppRadius.poster),
                        ),
                        alignment: watched
                            ? Alignment.topRight
                            : Alignment.bottomLeft,
                        child: watched
                            ? const Padding(
                                padding: EdgeInsets.all(5),
                                child: CircleAvatar(
                                  radius: 10,
                                  backgroundColor: AppColors.white,
                                  child: Icon(
                                    Icons.check_rounded,
                                    size: 14,
                                    color: AppColors.black,
                                  ),
                                ),
                              )
                            : const ProgressLine(value: 0.45),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: textTheme.titleSmall),
                            const SizedBox(height: 3),
                            Text(info, style: small),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case TourScene.downloads:
        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Simple image du bouton : normal, mais sans effet
              IgnorePointer(
                child: ExcludeFocus(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Télécharger · 12,4 Go'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const _Poster(shade: 0.6, width: 54),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Un film', style: textTheme.titleSmall),
                        const SizedBox(height: 8),
                        const ProgressLine(value: 0.58),
                        const SizedBox(height: 8),
                        Text('7,2 Go sur 12,4 Go', style: small),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      case TourScene.player:
        return switch (device) {
          TourDevice.touch => _Card(
            child: Row(
              children: [
                for (final (gesture, tap) in const [
                  ('Glisser : luminosité', 'Double appui : −10 s'),
                  ('Glisser : volume', 'Double appui : +10 s'),
                ])
                  Expanded(
                    child: Column(
                      children: [
                        const Icon(Icons.swipe_vertical_rounded, size: 30),
                        const SizedBox(height: 8),
                        Text(
                          gesture,
                          textAlign: TextAlign.center,
                          style: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(tap, textAlign: TextAlign.center, style: small),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          TourDevice.tv => _Card(
            child: Column(
              children: [for (final key in tvPlayerKeys) _KeyLine(key)],
            ),
          ),
          TourDevice.desktop => _Card(
            child: Column(
              children: [for (final key in desktopPlayerKeys) _KeyLine(key)],
            ),
          ),
        };
      case TourScene.profiles:
        return _Card(
          child: Column(
            children: [
              Text(
                'Qui regarde ?',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final (initial, filled) in const [
                    ('A', true),
                    ('B', false),
                    ('+', false),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      child: CircleAvatar(
                        radius: 32,
                        backgroundColor: filled
                            ? AppColors.white
                            : AppColors.surface3,
                        child: Text(
                          initial,
                          style: textTheme.titleLarge?.copyWith(
                            color: filled ? AppColors.black : AppColors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
    }
  }
}
