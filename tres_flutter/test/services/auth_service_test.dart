import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:tres_flutter/services/auth_service.dart';

void main() {
  test('isSignedIn reflects auth state and signOut clears session', () async {
    final user = MockUser(uid: 'user-1', email: 'user1@example.com');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final firestore = FakeFirebaseFirestore();
    final service = AuthService(auth: auth, firestore: firestore);

    expect(service.isSignedIn, isTrue);

    await service.signOut();

    expect(service.isSignedIn, isFalse);
  });
}
