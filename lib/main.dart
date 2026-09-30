import 'package:flutter/material.dart';

import 'screens/start_screen.dart';

void main() {
  // Nécessaire avant d'utiliser le coffre-fort du téléphone
  WidgetsFlutterBinding.ensureInitialized();
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
      ),
      home: const StartScreen(),
    );
  }
}
