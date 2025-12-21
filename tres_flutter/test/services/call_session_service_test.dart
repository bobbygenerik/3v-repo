import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:tres_flutter/services/call_session_service.dart';

void main() {
  test('startSession creates an active session', () async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'user-1', email: 'user1@example.com');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final service = CallSessionService(firestore: firestore, auth: auth);

    await service.startSession('room-123', ['user-1', 'user-2']);

    expect(service.currentSessionId, isNotNull);
    final doc = await firestore
        .collection('call_sessions')
        .doc(service.currentSessionId)
        .get();
    final data = doc.data();
    expect(data?['status'], 'active');
    expect((data?['participants'] as List).contains('user-1'), isTrue);
  });

  test('endSession marks session as ended', () async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'user-1', email: 'user1@example.com');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final service = CallSessionService(firestore: firestore, auth: auth);

    await service.startSession('room-123', ['user-1', 'user-2']);
    final sessionId = service.currentSessionId;
    await service.endSession();

    final doc = await firestore
        .collection('call_sessions')
        .doc(sessionId)
        .get();
    final data = doc.data();
    expect(data?['status'], 'ended');
    expect(data?['endedBy'], 'user-1');
  });
}
