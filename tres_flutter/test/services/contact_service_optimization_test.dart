import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tres_flutter/services/contact_service.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;
  late ContactService contactService;

  setUp(() async {
    // Use real mocks instead of trying to mock sealed classes
    mockAuth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: 'test-user-id',
        email: 'test@example.com',
      ),
    );
    
    fakeFirestore = FakeFirebaseFirestore();
    
    // Setup test data: 15 contacts
    final futures = <Future<void>>[];
    for (int i = 0; i < 15; i++) {
      futures.add(fakeFirestore
          .collection('users')
          .doc('test-user-id')
          .collection('contacts')
          .doc('contact-$i')
          .set({'addedAt': DateTime.now()}));
      
      // Add user data for each contact
      futures.add(fakeFirestore
          .collection('users')
          .doc('contact-$i')
          .set({
        'displayName': 'Contact $i',
        'email': 'contact$i@example.com',
      }));
    }
    await Future.wait(futures);
  });

  test('searchContacts performs batch queries correctly (N+1 optimization)', () async {
    contactService = ContactService(firestore: fakeFirestore, auth: mockAuth);

    // This should trigger batched queries internally
    final results = await contactService.searchContacts('Contact', limit: 20);

    // Verify we got all 15 contacts
    expect(results.length, 15, reason: 'Should return all 15 contacts');
    
    // Verify contact data is properly loaded
    expect(results.first['name'], contains('Contact'));
    expect(results.first['email'], contains('@example.com'));
  });
}
