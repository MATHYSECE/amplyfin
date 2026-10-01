import 'package:flutter/material.dart';

import '../models/session.dart';

/// Choix du menu « Compte ».
enum AccountAction { deviceInfo, logout }

/// Menu « Compte » (bouton en haut à droite) : qui est connecté, puis « Ce
/// que ton appareil sait lire » et « Se déconnecter ». Renvoie le choix, ou
/// null si on ferme le menu.
Future<AccountAction?> showAccountSheet(BuildContext context, Session session) {
  return showModalBottomSheet<AccountAction>(
    context: context,
    builder: (context) {
      void choose(AccountAction action) => Navigator.of(context).pop(action);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_rounded, size: 32),
              title: Text(
                session.userName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(session.serverUrl),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.memory_rounded),
              title: const Text('Ce que ton appareil sait lire'),
              subtitle: const Text('Formats vidéo, 4K, 10 bits, HDR'),
              onTap: () => choose(AccountAction.deviceInfo),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Se déconnecter'),
              onTap: () => choose(AccountAction.logout),
            ),
          ],
        ),
      );
    },
  );
}
