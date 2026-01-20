import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:tres_flutter/services/contact_service.dart';

void main() {
  group('ContactService', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late ContactService contactService;
    late MockUser user;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      user = MockUser(uid: 'user1', email: 'user@example.com');
      mockAuth = MockFirebaseAuth(mockUser: user, signedIn: true);
      contactService = ContactService(firestore: fakeFirestore, auth: mockAuth);
    });

    test('getFavoritesStream returns empty list initially when doc does not exist', () async {
      final favorites = await contactService.getFavoritesStream().first;
      expect(favorites, isEmpty);
    });

    test('toggleFavorite adds to favorites', () async {
      // Ensure user doc exists
      await fakeFirestore.collection('users').doc('user1').set({});

      await contactService.toggleFavorite('contact1');

      final doc = await fakeFirestore.collection('users').doc('user1').get();
      final favorites = List<String>.from(doc.data()!['favorites'] as List);
      expect(favorites, contains('contact1'));
    });

    test('toggleFavorite removes from favorites', () async {
      await fakeFirestore.collection('users').doc('user1').set({
        'favorites': ['contact1']
      });

      await contactService.toggleFavorite('contact1');

      final doc = await fakeFirestore.collection('users').doc('user1').get();
      final favorites = List<String>.from(doc.data()!['favorites'] as List);
      expect(favorites, isNot(contains('contact1')));
    });

    test('getFavoritesStream emits updates', () async {
      await fakeFirestore.collection('users').doc('user1').set({});

      // We need to wait for the stream to emit the initial value (empty)
      // then after toggle, it should emit the new value.

      final stream = contactService.getFavoritesStream();

      expectLater(
        stream,
        emitsInOrder([
           [],
           ['contact1'],
        ])
      );

      // Allow time for the first emission to be processed
      await Future.delayed(Duration.zero);

      await contactService.toggleFavorite('contact1');
    });
  });
}
