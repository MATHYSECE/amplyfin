import 'package:amplyfin/models/session.dart';
import 'package:amplyfin/services/offline_progress.dart';
import 'package:amplyfin/services/profile_data.dart';
import 'package:amplyfin/services/search_history.dart';
import 'package:amplyfin/services/session_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Session _session(String userId, {String token = 'jeton'}) => Session(
  serverUrl: 'https://serveur.exemple',
  accessToken: '$token-$userId',
  userId: userId,
  userName: 'Nom $userId',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    ProfileData.use(null);
  });

  group('Profils sur l\'appareil', () {
    test('la connexion d\'avant devient le premier profil', () async {
      FlutterSecureStorage.setMockInitialValues({
        'server_url': 'https://serveur.exemple',
        'access_token': 'ancien-jeton',
        'user_id': 'moi',
        'user_name': 'Mathys',
        'device_id': 'appareil',
      });
      SharedPreferences.setMockInitialValues({
        'search_history': ['Dune'],
        'series_languages_serie1': '{"audio":"fre"}',
        'library_sort_Movie': 'name', // réglage commun : ne bouge pas
      });
      final store = SessionStore();

      final session = await store.load();
      expect(session?.userId, 'moi');
      expect(session?.accessToken, 'ancien-jeton');
      expect(await store.profiles(), hasLength(1));
      // Même appareil et même adresse qu'avant
      expect(await store.deviceId(), 'appareil');
      expect(await store.lastServerUrl(), 'https://serveur.exemple');

      // Ses données sur l'appareil sont rangées sous son profil
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('profile.moi.search_history'), ['Dune']);
      expect(prefs.getString('profile.moi.series_languages_serie1'), isNotNull);
      expect(prefs.getString('library_sort_Movie'), 'name');
      expect(prefs.containsKey('search_history'), isFalse);
      expect(await SearchHistory().load(), ['Dune']);
    });

    test('personne n\'était connecté : aucun profil', () async {
      final store = SessionStore();
      expect(await store.load(), isNull);
      expect(await store.profiles(), isEmpty);
    });

    test('un deuxième compte s\'ajoute sans effacer le premier', () async {
      final store = SessionStore();
      await store.save(_session('moi'));
      await store.save(_session('maman'));

      expect((await store.profiles()).map((s) => s.userId), ['moi', 'maman']);
      expect((await store.load())?.userId, 'maman');
      expect(ProfileData.userId, 'maman');
    });

    test('même compte reconnecté : jeton mis à jour, même place', () async {
      final store = SessionStore();
      await store.save(_session('moi'));
      await store.save(_session('maman'));
      await store.save(_session('moi', token: 'nouveau'));

      final profiles = await store.profiles();
      expect(profiles.map((s) => s.userId), ['moi', 'maman']);
      expect(profiles.first.accessToken, 'nouveau-moi');
      expect((await store.load())?.userId, 'moi');
    });

    test('se déconnecter retire seulement le profil en cours', () async {
      final store = SessionStore();
      await store.save(_session('moi'));
      await store.save(_session('maman'));
      await store.clear();

      expect((await store.profiles()).map((s) => s.userId), ['moi']);
      expect(await store.load(), isNull);
      expect(ProfileData.userId, isNull);
    });
  });

  group('Données de chaque profil', () {
    test('positions hors ligne séparées', () async {
      final positions = OfflineProgress.instance;

      ProfileData.use('moi');
      await positions.record('film', position: const Duration(minutes: 30));
      expect(positions.of('film'), isNotNull);

      ProfileData.use('maman');
      await positions.init();
      expect(positions.of('film'), isNull);

      ProfileData.use('moi');
      await positions.init();
      expect(positions.of('film')?.position, const Duration(minutes: 30));
    });

    test('recherches récentes séparées', () async {
      ProfileData.use('moi');
      await SearchHistory().add('Dune');
      ProfileData.use('maman');
      expect(await SearchHistory().load(), isEmpty);
      ProfileData.use('moi');
      expect(await SearchHistory().load(), ['Dune']);
    });
  });
}
