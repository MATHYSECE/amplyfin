import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

/// Thème central d'Amplyfin : noir, blanc et quelques gris, police Manrope,
/// coins légèrement arrondis. Tous les écrans prennent leur style ici.

/// Couleurs de l'appli.
abstract final class AppColors {
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);

  /// Texte secondaire (infos, dates…).
  static const grey = Color(0xFFA3A3A3);

  /// Texte discret (légendes).
  static const greyDark = Color(0xFF8A8A8A);

  /// Texte long (résumés) : blanc adouci, plus reposant à lire.
  static const textSoft = Color(0xFFD6D6D6);

  /// Surfaces légèrement éclaircies (blocs, panneaux).
  static const surface1 = Color(0xFF0F0F0F);
  static const surface2 = Color(0xFF161616);
  static const surface3 = Color(0xFF1E1E1E);

  /// Effet « verre » : blanc très transparent, et son contour.
  static const glass = Color(0x0FFFFFFF); // 6 %
  static const glassStrong = Color(0x1AFFFFFF); // 10 %
  static const glassBorder = Color(0x21FFFFFF); // 13 %

  /// Contour plus marqué (pastilles de qualité, bordures des champs).
  static const outlineStrong = Color(0x38FFFFFF); // 22 %

  /// Halo des dégradés de fond, et halo secondaire plus discret.
  static const glow = Color(0x24FFFFFF); // 14 %
  static const glowSoft = Color(0x0FFFFFFF); // 6 %

  /// Barres de progression et jauges : fond, et partie déjà chargée.
  static const track = Color(0x33FFFFFF); // 20 %
  static const trackBuffer = Color(0x59FFFFFF); // 35 %

  /// Voiles noirs transparents (sur les images, sous les boutons en verre).
  static const scrim35 = Color(0x59000000);
  static const scrim55 = Color(0x8C000000);
  static const scrim70 = Color(0xB3000000);

  /// Erreurs (seule couleur, pour qu'une erreur reste bien visible).
  static const error = Color(0xFFFF7A7A);
}

/// Arrondis des coins.
abstract final class AppRadius {
  /// Affiches et vignettes : juste un peu arrondies.
  static const poster = 10.0;

  /// Blocs (choix audio, langues…).
  static const card = 18.0;

  /// Panneaux qui montent du bas, fenêtres.
  static const sheet = 28.0;

  /// Boutons et pastilles en forme de pilule.
  static const pill = 999.0;
}

/// Sous-titres (comme Plex) : texte blanc dans la police du téléphone
/// (SF Pro sur iPhone, Roboto sur Android), plus nette que Manrope en petit,
/// dans une boîte sombre arrondie autour du bloc de texte.
abstract final class AppSubtitles {
  static const text = AppColors.white;

  /// Fond de la boîte : noir à 60 %.
  static const box = Color(0x99000000);
  static const radius = 6.0;
  static const fontWeight = FontWeight.w500;
  static const lineHeight = 1.3;

  /// Police du système du téléphone.
  static String get fontFamily => defaultTargetPlatform == TargetPlatform.iOS
      ? 'CupertinoSystemText'
      : 'Roboto';
}

/// Durées des animations : courtes, pour une appli qui paraît fluide.
abstract final class AppDurations {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 280);
}

/// Construit le thème de l'appli.
ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.white,
    onPrimary: AppColors.black,
    secondary: AppColors.white,
    onSecondary: AppColors.black,
    tertiary: Color(0xFFBDBDBD),
    onTertiary: AppColors.black,
    error: AppColors.error,
    onError: AppColors.black,
    surface: AppColors.black,
    onSurface: AppColors.white,
    onSurfaceVariant: AppColors.grey,
    surfaceContainerLowest: AppColors.black,
    surfaceContainerLow: AppColors.surface1,
    surfaceContainer: AppColors.surface1,
    surfaceContainerHigh: AppColors.surface2,
    surfaceContainerHighest: AppColors.surface3,
    outline: AppColors.outlineStrong,
    outlineVariant: AppColors.glassBorder,
    inverseSurface: AppColors.white,
    onInverseSurface: AppColors.black,
    shadow: AppColors.black,
    scrim: AppColors.black,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Manrope',
    scaffoldBackgroundColor: AppColors.black,
    splashFactory: InkRipple.splashFactory,
    highlightColor: Colors.transparent,
  );

  final text = base.textTheme.copyWith(
    displaySmall: const TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w800,
      letterSpacing: -1,
      height: 1.05,
    ),
    headlineMedium: const TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
    ),
    headlineSmall: const TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    ),
    titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
    titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    titleSmall: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    bodyLarge: const TextStyle(fontSize: 15, height: 1.6),
    bodyMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    bodySmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    labelMedium: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    ),
    labelSmall: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    ),
  );

  const pillShape = StadiumBorder();

  return base.copyWith(
    textTheme: text.apply(
      bodyColor: AppColors.white,
      displayColor: AppColors.white,
    ),

    // Changements d'écran doux (fondu), comme sur les systèmes récents
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),

    // Bouton principal : pilule blanche, texte noir
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.black,
        disabledBackgroundColor: AppColors.glassStrong,
        minimumSize: const Size(64, 52),
        shape: pillShape,
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),

    // Bouton secondaire : pilule avec un fin contour
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.white,
        minimumSize: const Size(64, 48),
        shape: pillShape,
        side: const BorderSide(color: AppColors.glassBorder),
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.white,
        shape: pillShape,
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.white),
    ),

    // Affiches et vignettes : coins un peu arrondis, contenu découpé
    cardTheme: CardThemeData(
      color: AppColors.surface2,
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.poster),
      ),
    ),

    // Pastilles (genres, qualité, saisons)
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.glassStrong,
      selectedColor: AppColors.white,
      side: BorderSide.none,
      shape: pillShape,
      showCheckmark: false,
      labelStyle: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.white,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.black,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    ),

    // Panneaux qui montent du bas (choix de pistes, infos d'épisode)
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface2,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Color(0x40FFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface1,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface3,
      contentTextStyle: const TextStyle(
        fontFamily: 'Manrope',
        color: AppColors.white,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),

    // Champs de saisie (écran de connexion)
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.glass,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      labelStyle: const TextStyle(color: AppColors.grey),
      hintStyle: const TextStyle(color: AppColors.greyDark),
      prefixIconColor: AppColors.grey,
      suffixIconColor: AppColors.grey,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.white),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.error),
      ),
    ),

    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.white,
      textColor: AppColors.white,
      subtitleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.grey,
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: AppColors.glassBorder,
      thickness: 1,
      space: 1,
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.white,
      linearTrackColor: AppColors.glassStrong,
      circularTrackColor: Colors.transparent,
    ),
  );
}
