import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:tres_flutter/screens/call_chat_screen.dart';
import 'package:tres_flutter/firebase_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setupFirebaseCoreMocks();

  setUpAll(() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') {
        rethrow;
      }
    }
  });

  late FakeFirebaseFirestore fakeFirestore;

  Future<void> addMessage({
    required String callId,
    required String text,
    required int timestamp,
  }) async {
    await fakeFirestore
        .collection('call_chats')
        .doc(callId)
        .collection('messages')
        .add({
      'text': text,
      'senderId': 'sender_$callId',
      'senderName': 'Sender $callId',
      'timestamp': Timestamp.fromMillisecondsSinceEpoch(timestamp),
    });
  }

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    await addMessage(callId: 'call_1', text: 'message from call 1', timestamp: 1);
    await addMessage(callId: 'call_2', text: 'message from call 2', timestamp: 2);
  });

  testWidgets('CallChatScreen keeps showing same call stream across non-callId rebuilds', (WidgetTester tester) async {
    const callId = 'test_call_id';

    await addMessage(callId: callId, text: 'initial message', timestamp: 10);

    await tester.pumpWidget(MaterialApp(
      home: CallChatScreen(
        callId: callId,
        firestore: fakeFirestore,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('initial message'), findsOneWidget);

    // Rebuild with same callId and different title.
    await tester.pumpWidget(MaterialApp(
      home: CallChatScreen(
        callId: callId,
        callTitle: 'New Title',
        firestore: fakeFirestore,
      ),
    ));
    await tester.pumpAndSettle();

    // Same stream content should still be visible.
    expect(find.text('initial message'), findsOneWidget);

    // Add another message to same call; stream should still receive updates.
    await addMessage(callId: callId, text: 'second message', timestamp: 11);
    await tester.pumpAndSettle();

    expect(find.text('second message'), findsOneWidget);
  });

  testWidgets('CallChatScreen re-initializes stream when callId changes', (WidgetTester tester) async {
    const callId1 = 'call_1';
    const callId2 = 'call_2';

    await tester.pumpWidget(MaterialApp(
      home: CallChatScreen(
        callId: callId1,
        firestore: fakeFirestore,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('message from call 1'), findsOneWidget);
    expect(find.text('message from call 2'), findsNothing);

    // Rebuild with new callId
    await tester.pumpWidget(MaterialApp(
      home: CallChatScreen(
        callId: callId2,
        firestore: fakeFirestore,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('message from call 2'), findsOneWidget);
    expect(find.text('message from call 1'), findsNothing);
  });
}
