import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:tres_flutter/services/call_signaling_service.dart';

void main() {
  test('sendCallInvitation creates a pending invitation', () async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'caller-1', email: 'caller@example.com');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    await firestore.collection('users').doc('caller-1').set({
      'displayName': 'Caller One',
    });

    final service = CallSignalingService(firestore: firestore, auth: auth);

    final invitationId = await service.sendCallInvitation(
      recipientUserId: 'recipient-1',
      roomName: 'room-1',
      token: 'token',
      livekitUrl: 'wss://example.test',
    );

    expect(invitationId, isNotNull);
    final doc = await firestore.collection('call_invitations').doc(invitationId).get();
    final data = doc.data();
    expect(data?['status'], 'pending');
    expect(data?['recipientId'], 'recipient-1');
    expect(data?['callerId'], 'caller-1');
  });

  test('acceptInvitation updates status to accepted', () async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'caller-1', email: 'caller@example.com');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final service = CallSignalingService(firestore: firestore, auth: auth);

    final docRef = await firestore.collection('call_invitations').add({
      'callerId': 'caller-1',
      'recipientId': 'recipient-1',
      'roomName': 'room-1',
      'token': 'token',
      'livekitUrl': 'wss://example.test',
      'isVideoCall': true,
      'status': 'pending',
      'timestamp': Timestamp.fromDate(DateTime.now()),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 1))),
    });

    final accepted = await service.acceptInvitation(docRef.id);
    expect(accepted, isTrue);

    final updated = await firestore.collection('call_invitations').doc(docRef.id).get();
    expect(updated.data()?['status'], 'accepted');
  });
}
