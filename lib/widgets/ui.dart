import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Petits éléments visuels communs à tous les écrans.

/// Relie des infos par « · » en gardant chacune d'un seul tenant : le texte
/// ne passe à la ligne qu'entre deux infos (jamais au milieu de « E-AC3 »).
String joinInfos(Iterable<String> parts) => parts
    .map((part) => part.replaceAll(' ', ' ').replaceAll('-', '‑'))
    .join(' · ');

/// Fond noir avec un léger halo blanc en dégradé (en haut à gauche par
/// défaut, et un second plus discret en bas à droite).
class GlowBackground extends StatelessWidget {
  const GlowBackground({
    super.key,
    required this.child,
    this.center = const Alignment(-0.7, -1.1),
  });

  final Widget child;

  /// Position du halo principal.
  final Alignment center;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.black),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: center,
                  radius: 1.1,
                  colors: const [AppColors.glow, Colors.transparent],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(1.1, 1.1),
                  radius: 0.9,
                  colors: [AppColors.glowSoft, Colors.transparent],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Fine barre de progression (part déjà vue d'un film ou d'un épisode) :
/// blanc sur fond blanc transparent. [value] va de 0 à 1.
class ProgressLine extends StatelessWidget {
  const ProgressLine({
    super.key,
    required this.value,
    this.height = 3,
    this.rounded = false,
  });

  final double value;
  final double height;

  /// Bouts arrondis (barre seule), ou droits (collée au bas d'une image).
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(rounded ? height : 0);
    return Container(
      height: height,
      decoration: BoxDecoration(color: AppColors.track, borderRadius: radius),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: radius,
          ),
        ),
      ),
    );
  }
}

/// Bouton rond « en verre » (retour, déconnexion, infos…).
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 44,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.scrim35,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.glassBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.45, color: AppColors.white),
          ),
        ),
      ),
    );
  }
}

/// Bloc « en verre » : fond blanc très transparent et fin contour.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = AppRadius.card,
  });

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.glass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Pastille au contour fin (qualité du fichier : « 1080p », « HEVC »…).
class OutlinePill extends StatelessWidget {
  const OutlinePill(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        shape: const StadiumBorder(
          side: BorderSide(color: AppColors.outlineStrong),
        ),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

/// Onglets en forme de pilule : la pastille blanche glisse sous l'onglet
/// actif, en suivant le doigt quand on balaie d'un onglet à l'autre.
class PillTabs extends StatelessWidget {
  const PillTabs({super.key, required this.controller, required this.labels});

  final TabController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const ShapeDecoration(
        color: AppColors.glassStrong,
        shape: StadiumBorder(side: BorderSide(color: AppColors.glass)),
      ),
      child: SizedBox(
        height: 38,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tabWidth = constraints.maxWidth / labels.length;
            return AnimatedBuilder(
              animation: controller.animation!,
              builder: (context, _) {
                final position = controller.animation!.value;
                return Stack(
                  children: [
                    Positioned(
                      left: position * tabWidth,
                      width: tabWidth,
                      top: 0,
                      bottom: 0,
                      child: const DecoratedBox(
                        decoration: ShapeDecoration(
                          color: AppColors.white,
                          shape: StadiumBorder(),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < labels.length; i++)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: controller.index == i,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => controller.animateTo(i),
                                child: Center(
                                  child: Text(
                                    labels[i],
                                    style: style?.copyWith(
                                      // Texte noir sur la pastille, gris ailleurs
                                      color: Color.lerp(
                                        AppColors.grey,
                                        AppColors.black,
                                        (1 - (position - i).abs()).clamp(
                                          0.0,
                                          1.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Zone grise animée (un reflet la traverse) affichée pendant un
/// chargement, à la place d'une roue : la page garde déjà sa forme.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = AppRadius.poster,
  });

  final double? width;
  final double? height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 3 - 1.5;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 1, 0),
              end: Alignment(t + 1, 0),
              colors: const [
                AppColors.surface1,
                AppColors.surface3,
                AppColors.surface1,
              ],
            ),
          ),
        );
      },
    );
  }
}
