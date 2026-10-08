import 'package:amplyfin/models/session.dart';
import 'package:amplyfin/screens/profiles_screen.dart';
import 'package:amplyfin/services/profile_data.dart';
import 'package:amplyfin/services/profile_switch.dart';
import 'package:amplyfin/services/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Session _session(String userId, String name, {String? imageTag}) => Session(
  serverUrl: 'https://serveur.exemple',
  accessToken: 'jeton-$userId',
  userId: userId,
  userName: name,
  imageTag: imageTag,
);

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    ProfileData.use(null);
  });

  group('Initiales', () {
    test('prénom composé, nom et prénom, un seul mot', () {
      expect(initialsOf('Marie-Claire'), 'MC');
      expect(initialsOf('jean dupont'), 'JD');
      expect(initialsOf('Mathys'), 'M');
      expect(initialsOf('  '), '?');
    });
  });

  group('« Qui regarde ? » à l\'ouverture', () {
    test('télé et tablette oui, téléphone non', () {
      expect(askWhoIsWatching(tv: true, tablet: false), isTrue);
      expect(askWhoIsWatching(tv: false, tablet: true), isTrue);
      expect(askWhoIsWatching(tv: false, tablet: false), isFalse);
    });
  });

  group('Profils', () {
    test('photo gardée avec le profil', () {
      final copy = Session.fromJson(
        _session('moi', 'Mathys', imageTag: 'abc').toJson(),
      );
      expect(copy.imageTag, 'abc');
      final updated = copy.withProfile(userName: 'Mathys P.', imageTag: null);
      expect(updated.imageTag, isNull);
      expect(updated.accessToken, 'jeton-moi');
    });

    test('choisir puis retirer un profil', () async {
      final store = SessionStore();
      await store.save(_session('moi', 'Mathys'));
      await store.save(_session('maman', 'Sophie'));

      await store.select(_session('moi', 'Mathys'));
      expect((await store.load())?.userId, 'moi');
      expect(ProfileData.userId, 'moi');

      // Retirer un autre profil ne change pas le profil en cours
      await store.remove(_session('maman', 'Sophie'));
      expect((await store.profiles()).map((s) => s.userId), ['moi']);
      expect((await store.load())?.userId, 'moi');
    });
  });

  testWidgets('l\'écran montre chaque personne et « Ajouter un profil »', (
    tester,
  ) async {
    final store = SessionStore();
    await store.save(_session('moi', 'Mathys'));
    await store.save(_session('maman', 'Sophie Martin'));

    await tester.pumpWidget(const MaterialApp(home: ProfilesScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Qui regarde ?'), findsOneWidget);
    expect(find.text('Mathys'), findsOneWidget);
    expect(find.text('Sophie Martin'), findsOneWidget);
    expect(find.text('SM'), findsOneWidget); // pas de photo : initiales
    expect(find.text('Ajouter un profil'), findsOneWidget);

    // « Ajouter un profil » ouvre la connexion, avec un retour possible
    await tester.tap(find.text('Ajouter un profil'));
    await tester.pumpAndSettle();
    expect(find.text('Se connecter'), findsOneWidget);
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('Qui regarde ?'), findsOneWidget);
  });

  testWidgets('appui long : retirer un profil, les autres restent', (
    tester,
  ) async {
    final store = SessionStore();
    await store.save(_session('moi', 'Mathys'));
    await store.save(_session('maman', 'Sophie Martin'));

    await tester.pumpWidget(const MaterialApp(home: ProfilesScreen()));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Sophie Martin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retirer ce profil'));
    await tester.pumpAndSettle();
    // Confirmation, puis le serveur (absent en test) ne bloque pas le retrait
    await tester.runAsync(() async {
      await tester.tap(find.text('Retirer'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Sophie Martin'), findsNothing);
    expect(find.text('Mathys'), findsOneWidget);
    expect((await store.profiles()).map((s) => s.userId), ['moi']);
  });
}
