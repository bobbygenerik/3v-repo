import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:tres_flutter/services/contact_service.dart';

void main() {
  group('ContactService', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late ContactService service;
    late MockUser user;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      user = MockUser(uid: 'user-1', email: 'user@example.com');
      auth = MockFirebaseAuth(mockUser: user, signedIn: true);

      // Ensure user document exists
      await firestore.collection('users').doc('user-1').set({
        'email': 'user@example.com',
        'displayName': 'Test User',
        'favorites': [],
      });

      service = ContactService(firestore: firestore, auth: auth);
    });

    test('toggleFavorite adds favorite if not present', () async {
      await service.toggleFavorite('contact-1');

      final doc = await firestore.collection('users').doc('user-1').get();
      final favorites = List<String>.from(doc.data()?['favorites'] ?? []);
      expect(favorites, contains('contact-1'));
    });

    test('toggleFavorite removes favorite if present', () async {
      // Setup initial favorite
      await firestore.collection('users').doc('user-1').update({
        'favorites': FieldValue.arrayUnion(['contact-1'])
      });

      await service.toggleFavorite('contact-1');

      final doc = await firestore.collection('users').doc('user-1').get();
      final favorites = List<String>.from(doc.data()?['favorites'] ?? []);
      expect(favorites, isNot(contains('contact-1')));
    });

    test('isFavorite returns correct status', () async {
      expect(await service.isFavorite('contact-1'), isFalse);

      await firestore.collection('users').doc('user-1').update({
        'favorites': FieldValue.arrayUnion(['contact-1'])
      });

      expect(await service.isFavorite('contact-1'), isTrue);
    });

    test('favoritesStream emits updates', () async {
      expect(service.favoritesStream, emitsInOrder([
        [], // Initial empty
        ['contact-1'], // After add
        [], // After remove
      ]));

      await service.toggleFavorite('contact-1');
      await service.toggleFavorite('contact-1');
    });
  });
}
