import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tres_flutter/screens/call_chat_screen.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

void main() {
  late MockFirebaseFirestore mockFirestore;
  late MockCollectionReference mockCallChatsCollection;
  late MockDocumentReference mockCallDoc;
  late MockCollectionReference mockMessagesCollection;
  late MockQuery mockQuery;
  late Stream<QuerySnapshot<Map<String, dynamic>>> mockStream;

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockCallChatsCollection = MockCollectionReference();
    mockCallDoc = MockDocumentReference();
    mockMessagesCollection = MockCollectionReference();
    mockQuery = MockQuery();

    // Create a dummy stream
    mockStream = const Stream.empty();

    // Setup the chain
    when(
      () => mockFirestore.collection('call_chats'),
    ).thenReturn(mockCallChatsCollection);
    when(() => mockCallChatsCollection.doc(any())).thenReturn(mockCallDoc);
    when(
      () => mockCallDoc.collection('messages'),
    ).thenReturn(mockMessagesCollection);
    when(
      () => mockMessagesCollection.orderBy('timestamp', descending: true),
    ).thenReturn(mockQuery);
    when(() => mockQuery.limit(100)).thenReturn(mockQuery);
    when(() => mockQuery.snapshots()).thenAnswer((_) => mockStream);
  });

  testWidgets('CallChatScreen initializes stream only once across rebuilds', (
    WidgetTester tester,
  ) async {
    const callId = 'test_call_id';

    await tester.pumpWidget(
      MaterialApp(
        home: CallChatScreen(callId: callId, firestore: mockFirestore),
      ),
    );

    // Verify snapshots() called once
    verify(() => mockQuery.snapshots()).called(1);

    // Rebuild the widget with same parameters but different title to trigger build
    await tester.pumpWidget(
      MaterialApp(
        home: CallChatScreen(
          callId: callId,
          callTitle: 'New Title',
          firestore: mockFirestore,
        ),
      ),
    );

    // Verify snapshots() was NOT called again.
    // verifyNever implies called(0). verify(...).called(0) is equivalent.
    // Important: verify checks calls *since the last verification* if using `called`?
    // No, mocktail verify checks history.
    // If we want to check that it was NOT called *again*, we should check total calls is still 1.
    // But `called(1)` "consumes" the calls in some mocking frameworks.
    // In mocktail: "The verify method verifies that a method on a mock object was called with the given arguments."

    // Let's verify total calls.
    // Actually, simply using verifyNever is risky if it checks full history.
    // The documentation says: "Verifies that a method on a mock object was never called with the given arguments."
    // If it was called before, verifyNever will fail.

    // So we should verify that no *new* interactions happened.
    // Or simpler: reset the mock.
    clearInteractions(mockQuery);

    // Rebuild again
    await tester.pumpWidget(
      MaterialApp(
        home: CallChatScreen(
          callId: callId,
          callTitle: 'Another Title',
          firestore: mockFirestore,
        ),
      ),
    );

    // Now verify never called
    verifyNever(() => mockQuery.snapshots());
  });

  testWidgets('CallChatScreen re-initializes stream when callId changes', (
    WidgetTester tester,
  ) async {
    const callId1 = 'call_1';
    const callId2 = 'call_2';

    await tester.pumpWidget(
      MaterialApp(
        home: CallChatScreen(callId: callId1, firestore: mockFirestore),
      ),
    );

    verify(() => mockQuery.snapshots()).called(1);

    clearInteractions(mockQuery);

    // Rebuild with new callId
    await tester.pumpWidget(
      MaterialApp(
        home: CallChatScreen(callId: callId2, firestore: mockFirestore),
      ),
    );

    // Should be called again once
    verify(() => mockQuery.snapshots()).called(1);
  });
}
