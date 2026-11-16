import 'package:flutter/material.dart';

import '../models/genre.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Carte d'un genre (« Parcourir par genre ») : son nom seul sur un bloc en
/// verre (pas d'image, qui mettait trop longtemps à charger). S'enfonce un
/// peu à l'appui.
class GenreCard extends StatelessWidget {
  const GenreCard({super.key, required this.genre, required this.onTap});

  final Genre genre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
          // Léger dégradé : plus clair en haut à gauche, comme un reflet
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.glassStrong, AppColors.glass],
          ),
        ),
        child: Text(
          genre.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
