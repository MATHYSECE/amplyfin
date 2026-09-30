import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/start_screen.dart';

void main() {
  // Nécessaire avant d'utiliser le coffre-fort du téléphone
  WidgetsFlutterBinding.ensureInitialized();
  // Prépare le moteur vidéo (media_kit)
  MediaKit.ensureInitialized();
  runApp(const AmplyfinApp());
}

class AmplyfinApp extends StatelessWidget {
  const AmplyfinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Amplyfin',
      debugShowCheckedModeBanner: false,
      // Thème sombre, couleur inspirée de Jellyfin
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF00A4DC),
        brightness: Brightness.dark,
        // Cartes (affiches) : coins arrondis, contenu découpé à l'arrondi
        cardTheme: CardThemeData(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      home: const StartScreen(),
    );
  }
}
