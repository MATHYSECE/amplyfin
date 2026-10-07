import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/start_screen.dart';
import 'services/device_capabilities.dart';
import 'services/download_manager.dart';
import 'theme/app_theme.dart';
import 'widgets/tv_focus.dart';

Future<void> main() async {
  // Nécessaire avant d'utiliser le coffre-fort du téléphone
  WidgetsFlutterBinding.ensureInitialized();
  // Télé ou pas : l'interface en dépend dès le premier écran
  await DeviceCapabilities.detectTv();
  // Télé : la page suit la sélection de la télécommande, et OK maintenu
  // ne se répète pas
  if (DeviceCapabilities.isTv) {
    followTvFocus();
    ignoreTvOkRepeats();
  }
  // Prépare le moteur vidéo (media_kit)
  MediaKit.ensureInitialized();
  // Reprend le suivi des téléchargements (terminés ou en cours)
  unawaited(DownloadManager.instance.init());
  // Licence de la police Manrope, ajoutée aux mentions légales de l'appli
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Manrope'], text);
  });
  // Barres du système transparentes : le fond noir va jusqu'aux bords
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
  runApp(const AmplyfinApp());
}

class AmplyfinApp extends StatelessWidget {
  const AmplyfinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Amplyfin',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(tv: DeviceCapabilities.isTv),
      // Télé : tout est réduit (vu de loin, l'écran paraît plus petit)
      builder: DeviceCapabilities.isTv
          ? (context, child) => TvScale(child: child!)
          : null,
      home: const StartScreen(),
    );
  }
}
