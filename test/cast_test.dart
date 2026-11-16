import 'package:amplyfin/models/item_details.dart';
import 'package:amplyfin/models/watch_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('castFromJson', () {
    test('acteurs d\'abord, puis réalisation, sans doublon', () {
      final cast = castFromJson([
        {'Id': 'd', 'Name': 'Denis V.', 'Type': 'Director'},
        {'Id': 'a', 'Name': 'Tim C.', 'Type': 'Actor', 'Role': 'Paul'},
        {'Id': 'w', 'Name': 'Jon S.', 'Type': 'Writer'},
        {'Id': 'a', 'Name': 'Tim C.', 'Type': 'Actor', 'Role': 'Paul'},
        {'Id': 'b', 'Name': 'Zen D.', 'Type': 'Actor', 'Role': ' '},
      ]);
      expect(cast.map((p) => p.id), ['a', 'b', 'd']);
      expect(cast[0].role, 'Paul');
      expect(cast[1].role, isNull);
      expect(cast[2].role, 'Réalisation');
    });

    test('liste absente ou trop longue', () {
      expect(castFromJson(null), isEmpty);
      final many = [
        for (var i = 0; i < 40; i++)
          {'Id': '$i', 'Name': 'Personne $i', 'Type': 'Actor'},
      ];
      expect(castFromJson(many), hasLength(20));
    });

    test('photo et initiales', () {
      final person = castFromJson([
        {
          'Id': 'a',
          'Name': 'Omar Sy',
          'Type': 'Actor',
          'PrimaryImageTag': 'abc',
        },
      ]).single;
      expect(person.imageTag, 'abc');
      expect(person.initials, 'OS');
    });
  });

  test('favori lu dans UserData', () {
    expect(WatchProgress.fromUserData({'IsFavorite': true}).favorite, isTrue);
    expect(WatchProgress.fromUserData({}).favorite, isFalse);
    expect(WatchProgress.fromUserData(null).favorite, isFalse);
  });
}
