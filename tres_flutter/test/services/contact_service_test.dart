import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tres_flutter/services/contact_service.dart';

void main() {
  group('ContactService favorites stream', () {
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

    test('getFavoritesStream returns empty list initially when doc does not exist',
        () async {
      final favorites = await contactService.getFavoritesStream().first;
      expect(favorites, isEmpty);
    });

    test('toggleFavorite adds to favorites', () async {
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

    test('getFavoritesStream emits update containing added favorite', () async {
      await fakeFirestore.collection('users').doc('user1').set({});

      final stream = contactService.getFavoritesStream();

      final emittedFuture = stream.firstWhere(
        (favorites) => favorites.contains('contact1'),
      );

      await Future.delayed(Duration.zero);
      await contactService.toggleFavorite('contact1');

      final emitted = await emittedFuture;
      expect(emitted, contains('contact1'));
    });
  });

  group('ContactService ChangeNotifier', () {
    late MockFirebaseAuth auth;
    late FakeFirebaseFirestore firestore;
    late ContactService service;
    final user = MockUser(uid: 'user-1', email: 'user1@example.com');

    setUp(() async {
      auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      firestore = FakeFirebaseFirestore();

      await firestore.collection('users').doc(user.uid).set({
        'email': 'user1@example.com',
        'favorites': <String>[],
      });

      service = ContactService(auth: auth, firestore: firestore);
      await Future.delayed(Duration.zero);
    });

    test('isFavorite returns false initially', () {
      expect(service.isFavorite('contact-1'), isFalse);
    });

    test('toggleFavorite adds contact to favorites', () async {
      await service.toggleFavorite('contact-1');

      expect(service.isFavorite('contact-1'), isTrue);

      final doc = await firestore.collection('users').doc(user.uid).get();
      final favorites = List<String>.from(doc.data()!['favorites']);
      expect(favorites, contains('contact-1'));
    });

    test('toggleFavorite removes contact from favorites', () async {
      await service.toggleFavorite('contact-1');
      expect(service.isFavorite('contact-1'), isTrue);

      await service.toggleFavorite('contact-1');
      expect(service.isFavorite('contact-1'), isFalse);

      final doc = await firestore.collection('users').doc(user.uid).get();
      final favorites = List<String>.from(doc.data()!['favorites']);
      expect(favorites, isNot(contains('contact-1')));
    });
  });

  group('ContactService searchContacts', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late ContactService contactService;
    late MockUser user;

    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();
      user = MockUser(uid: 'user1', email: 'user@example.com');
      mockAuth = MockFirebaseAuth(mockUser: user, signedIn: true);
      contactService = ContactService(firestore: fakeFirestore, auth: mockAuth);

      // Seed data
      // 1. Create contacts in subcollection
      // 2. Create actual user docs for those contacts
      final batch = fakeFirestore.batch();
      for (int i = 0; i < 15; i++) {
        final uid = 'contact-$i';
        // Add to contacts subcollection
        batch.set(
          fakeFirestore
              .collection('users')
              .doc('user1')
              .collection('contacts')
              .doc(uid),
          <String, dynamic>{},
        );

        // Add user profile
        batch.set(
          fakeFirestore.collection('users').doc(uid),
          <String, dynamic>{
            'name': 'Contact $i',
            'email': 'contact$i@example.com',
          },
        );
      }

      // Add one more contact that doesn't match search
      batch.set(
        fakeFirestore
            .collection('users')
            .doc('user1')
            .collection('contacts')
            .doc('other-guy'),
        <String, dynamic>{},
      );
      batch.set(
        fakeFirestore.collection('users').doc('other-guy'),
        <String, dynamic>{
          'name': 'Other Guy',
          'email': 'other@example.com',
        },
      );

      await batch.commit();
    });

    test('returns correct filtered contacts', () async {
      final results = await contactService.searchContacts('Contact 1');
      // Should match Contact 1, Contact 10, Contact 11, Contact 12, Contact 13, Contact 14
      // But default limit is 5.

      expect(results.length, 5);
      expect(results.first['name'], contains('Contact'));
    });

    test('returns correct contact by exact email', () async {
      final results =
          await contactService.searchContacts('contact5@example.com');
      expect(results.length, 1);
      expect(results.first['uid'], 'contact-5');
      expect(results.first['name'], 'Contact 5');
    });

    test('handles pagination/batches correctly (finds item in second batch)',
        () async {
      // 'Contact 14' is the last one (index 14).
      // If batching works (10 then 5), it should be found in the second batch.
      final results = await contactService.searchContacts('Contact 14');
      expect(results.length, 1);
      expect(results.first['uid'], 'contact-14');
    });

    test('returns empty list if no matches', () async {
      final results = await contactService.searchContacts('NonExistent');
      expect(results, isEmpty);
    });

    test('respects limit parameter', () async {
      final results = await contactService.searchContacts('Contact', limit: 10);
      expect(results.length, 10);
    });
  });
}
