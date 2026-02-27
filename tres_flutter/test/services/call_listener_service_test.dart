import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:tres_flutter/services/call_listener_service.dart';

void main() {
  test('startListening surfaces pending invitations', () async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'user-1', email: 'user1@example.com');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final service = CallListenerService(firestore: firestore, auth: auth);

    service.startListening();

    await firestore.collection('call_invitations').add({
      'callerId': 'caller-1',
      'callerName': 'Caller',
      'recipientId': 'user-1',
      'roomName': 'room-1',
      'token': 'token',
      'livekitUrl': 'wss://example.test',
      'isVideoCall': true,
      'status': 'pending',
      'timestamp': Timestamp.now(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(minutes: 1)),
      ),
    });

    await Future.delayed(const Duration(milliseconds: 10));

    expect(service.hasIncomingCall, isTrue);
    service.clearIncomingCall();
    expect(service.hasIncomingCall, isFalse);
  });
}
