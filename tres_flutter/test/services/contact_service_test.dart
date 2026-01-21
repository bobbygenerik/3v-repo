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

    test('getFavoritesStream emits updates', () async {
      await fakeFirestore.collection('users').doc('user1').set({});

      final stream = contactService.getFavoritesStream();

      expectLater(
        stream,
        emitsInOrder([
          [],
          ['contact1'],
        ]),
      );

      await Future.delayed(Duration.zero);
      await contactService.toggleFavorite('contact1');
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
}
