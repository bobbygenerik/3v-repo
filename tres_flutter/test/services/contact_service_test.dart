import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:tres_flutter/services/contact_service.dart';

void main() {
  group('ContactService', () {
    late MockFirebaseAuth auth;
    late FakeFirebaseFirestore firestore;
    late ContactService service;
    final user = MockUser(uid: 'user-1', email: 'user1@example.com');

    setUp(() async {
      auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      firestore = FakeFirebaseFirestore();

      // Seed user data
      await firestore.collection('users').doc(user.uid).set({
        'email': 'user1@example.com',
        'favorites': <String>[],
      });

      service = ContactService(auth: auth, firestore: firestore);
      // Wait for auth listener to trigger subscription
      await Future.delayed(Duration.zero);
    });

    test('isFavorite returns false initially', () {
      expect(service.isFavorite('contact-1'), isFalse);
    });

    test('toggleFavorite adds contact to favorites', () async {
      await service.toggleFavorite('contact-1');

      // Check local state
      expect(service.isFavorite('contact-1'), isTrue);

      // Check Firestore
      final doc = await firestore.collection('users').doc(user.uid).get();
      final favorites = List<String>.from(doc.data()!['favorites']);
      expect(favorites, contains('contact-1'));
    });

    test('toggleFavorite removes contact from favorites', () async {
      // Add first
      await service.toggleFavorite('contact-1');
      expect(service.isFavorite('contact-1'), isTrue);

      // Remove
      await service.toggleFavorite('contact-1');
      expect(service.isFavorite('contact-1'), isFalse);

      // Check Firestore
      final doc = await firestore.collection('users').doc(user.uid).get();
      final favorites = List<String>.from(doc.data()!['favorites']);
      expect(favorites, isNot(contains('contact-1')));
    });
  });
}
