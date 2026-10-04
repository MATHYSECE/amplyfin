import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/jellyfin_api.dart';
import '../models/home_items.dart';
import '../services/device_capabilities.dart';
import '../theme/app_theme.dart';
import 'media_row.dart';

/// « À la une » en haut de l'accueil : les nouveautés défilent toutes
/// seules (fondu et léger zoom sur l'image), ou au doigt. Sur un téléphone,
/// une grande carte ; sur une tablette, une bannière sur toute la largeur
/// avec le résumé.
class HomeHero extends StatefulWidget {
  const HomeHero({
    super.key,
    required this.api,
    required this.items,
    required this.onPlay,
    required this.onInfo,
  });

  final JellyfinApi api;
  final List<HeroItem> items;
  final void Function(HeroItem item) onPlay;
  final void Function(HeroItem item) onInfo;

  /// Temps passé sur chaque nouveauté.
  static const _interval = Duration(seconds: 6);

  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(HomeHero._interval, (_) => _go(_index + 1));
  }

  void _go(int index) {
    final count = widget.items.length;
    if (count == 0 || !mounted) return;
    setState(() => _index = (index % count + count) % count);
  }

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayout.of(context);
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final current = items[_index.clamp(0, items.length - 1)];
    final width = MediaQuery.sizeOf(context).width;

    final card = GestureDetector(
      // Glisser vers la gauche ou la droite : nouveauté suivante / précédente
      onHorizontalDragEnd: (details) {
        final speed = details.primaryVelocity ?? 0;
        if (speed.abs() < 200) return;
        _go(_index + (speed < 0 ? 1 : -1));
        _restartTimer();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Images : fondu de l'une à l'autre
          for (final (i, item) in items.indexed)
            AnimatedOpacity(
              opacity: i == _index ? 1 : 0,
              duration: const Duration(milliseconds: 800),
              child: _HeroImage(api: widget.api, item: item, zoom: i == _index),
            ),
          // Voile pour lire le texte
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: layout.isWide
                  ? const LinearGradient(
                      colors: [AppColors.scrim70, Colors.transparent],
                      stops: [0, 0.7],
                    )
                  : const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.35, 0.65, 1],
                      colors: [
                        Colors.transparent,
                        AppColors.scrim55,
                        AppColors.black,
                      ],
                    ),
            ),
          ),
          if (layout.isWide)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.25, 0.7, 1],
                  colors: [
                    AppColors.scrim55,
                    Colors.transparent,
                    Colors.transparent,
                    AppColors.black,
                  ],
                ),
              ),
            ),
          Positioned(
            left: layout.isWide ? layout.gutter : 20,
            right: layout.isWide ? null : 20,
            bottom: layout.isWide ? 34 : 18,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: layout.isWide ? 480 : double.infinity,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Texte : glisse un peu en changeant de nouveauté
                  AnimatedSwitcher(
                    duration: AppDurations.medium,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.bottomLeft,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0, 0.08),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _HeroText(
                      key: ValueKey(current.item.id),
                      item: current,
                      wide: layout.isWide,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _HeroButton(
                        filled: true,
                        wide: layout.isWide,
                        icon: Icons.play_arrow_rounded,
                        label: 'Lecture',
                        onPressed: () => widget.onPlay(current),
                      ),
                      const SizedBox(width: 10),
                      _HeroButton(
                        filled: false,
                        wide: layout.isWide,
                        icon: Icons.info_outline_rounded,
                        label: 'Infos',
                        onPressed: () => widget.onInfo(current),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Points : où on en est
          Positioned(
            right: layout.isWide ? layout.gutter : 16,
            top: layout.isWide ? null : 16,
            bottom: layout.isWide ? 50 : null,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  GestureDetector(
                    onTap: () {
                      _go(i);
                      _restartTimer();
                    },
                    child: AnimatedContainer(
                      duration: AppDurations.medium,
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.only(left: 6),
                      width: i == _index ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _index ? AppColors.white : AppColors.track,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    // Coupé aux bords : l'image qui zoome ne déborde pas sous le dégradé
    if (layout.isWide) {
      return SizedBox(height: 470, child: ClipRect(child: card));
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.gutter),
      child: SizedBox(
        height: (width - layout.gutter * 2) * 1.2,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: card,
        ),
      ),
    );
  }
}

/// Image de fond d'une nouveauté (l'affiche si elle n'en a pas), qui
/// recule doucement chaque fois qu'elle revient à l'écran ([zoom]).
class _HeroImage extends StatefulWidget {
  const _HeroImage({required this.api, required this.item, required this.zoom});

  final JellyfinApi api;
  final HeroItem item;
  final bool zoom;

  @override
  State<_HeroImage> createState() => _HeroImageState();
}

class _HeroImageState extends State<_HeroImage>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  @override
  void initState() {
    super.initState();
    if (widget.zoom) _controller.forward();
  }

  @override
  void didUpdateWidget(_HeroImage old) {
    super.didUpdateWidget(old);
    if (widget.zoom && !old.zoom) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pixels =
        MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    final width = ((pixels / 200).ceil() * 200).clamp(400, 1920);
    final url =
        widget.api.backdropUrl(widget.item.details, width: width) ??
        widget.api.posterUrl(widget.item.item, width: 600);
    final image = url == null
        ? const ColoredBox(color: AppColors.surface2)
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            fadeInDuration: AppDurations.medium,
            placeholder: (_, _) => const ColoredBox(color: AppColors.surface1),
            errorWidget: (_, _, _) =>
                const ColoredBox(color: AppColors.surface2),
          );
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.scale(
        scale: 1.12 - 0.12 * Curves.easeOut.transform(_controller.value),
        child: child,
      ),
      child: image,
    );
  }
}

/// Petit texte, titre, infos (et résumé sur une tablette).
class _HeroText extends StatelessWidget {
  const _HeroText({super.key, required this.item, required this.wide});

  final HeroItem item;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final overview = item.details.overview?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.eyebrow.toUpperCase(),
          style: textTheme.labelSmall?.copyWith(
            color: AppColors.textSoft,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          item.item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: (wide ? textTheme.displaySmall : textTheme.headlineMedium)
              ?.copyWith(fontSize: wide ? 44 : 30, height: 1.05),
        ),
        const SizedBox(height: 8),
        Text(
          item.infoLine,
          style: textTheme.bodyMedium?.copyWith(
            color: AppColors.textSoft,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (wide && overview.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            overview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyLarge?.copyWith(color: AppColors.textSoft),
          ),
        ],
      ],
    );
  }
}

/// « Lecture » (blanc) et « Infos » (verre) : la moitié de la largeur
/// chacun sur un téléphone.
class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.filled,
    required this.wide,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool filled;
  final bool wide;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final size = Size(wide ? 150 : 0, 46);
    final button = filled
        ? FilledButton.icon(
            onPressed: onPressed,
            // Télé : « Lecture » sélectionné à l'arrivée sur l'accueil
            autofocus: DeviceCapabilities.isTv,
            style: FilledButton.styleFrom(minimumSize: size),
            icon: Icon(icon, size: 22),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: size,
              // Télé : la couleur suit la sélection (thème)
              backgroundColor: DeviceCapabilities.isTv
                  ? null
                  : AppColors.glassStrong,
            ),
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
    return wide ? button : Expanded(child: button);
  }
}
