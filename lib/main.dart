import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'api/jellyfin_api.dart';
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
  // Ordinateur ou pas : pareil (souris, clavier, fenêtre)
  DeviceCapabilities.detectDesktop();
  // Télé : la page suit la sélection de la télécommande, et OK maintenu
  // ne se répète pas
  if (DeviceCapabilities.isTv) {
    followTvFocus();
    ignoreTvOkRepeats();
  }
  // Prépare le moteur vidéo (media_kit), absent des télés Samsung
  if (!DeviceCapabilities.isTizen) MediaKit.ensureInitialized();
  // Vraie version de l'appli (Paramètres, en-tête envoyé au serveur)
  await JellyfinApi.loadClientVersion();
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

  static final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Amplyfin',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: buildAppTheme(tv: DeviceCapabilities.isTv),
      // Télé : tout est réduit (vu de loin, l'écran paraît plus petit)
      builder: DeviceCapabilities.isTv
          ? (context, child) => TvScale(child: child!)
          : DeviceCapabilities.isDesktop
          ? (context, child) =>
                _DesktopBack(navigator: _navigatorKey, child: child!)
          : null,
      home: const StartScreen(),
    );
  }
}

/// PC : bouton « précédent » de la souris et Échap reviennent à l'écran
/// d'avant (comme la flèche Retour). Le lecteur garde Échap pour quitter
/// le plein écran.
class _DesktopBack extends StatelessWidget {
  const _DesktopBack({required this.navigator, required this.child});

  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  void _back() => navigator.currentState?.maybePop();

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (event.buttons & kBackMouseButton != 0) _back();
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _back},
        child: child,
      ),
    );
  }
}
