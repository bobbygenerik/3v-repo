import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tres_flutter/services/contact_service.dart';

// Mocks
class MockFirebaseAuth extends Mock implements FirebaseAuth {}
class MockUser extends Mock implements User {}
class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}
class MockCollectionReference extends Mock implements CollectionReference<Map<String, dynamic>> {}
class MockDocumentReference extends Mock implements DocumentReference<Map<String, dynamic>> {}
class MockQuery extends Mock implements Query<Map<String, dynamic>> {}
class MockQuerySnapshot extends Mock implements QuerySnapshot<Map<String, dynamic>> {}
class MockDocumentSnapshot extends Mock implements DocumentSnapshot<Map<String, dynamic>> {}
class MockQueryDocumentSnapshot extends Mock implements QueryDocumentSnapshot<Map<String, dynamic>> {}

void main() {
  late MockFirebaseAuth mockAuth;
  late MockUser mockUser;
  late MockFirebaseFirestore mockFirestore;
  late MockCollectionReference mockUsersCollection;
  late MockDocumentReference mockUserDoc;
  late MockCollectionReference mockContactsCollection;
  late MockQuerySnapshot mockContactsSnapshot;

  late ContactService contactService;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockUser = MockUser();
    mockFirestore = MockFirebaseFirestore();
    mockUsersCollection = MockCollectionReference();
    mockUserDoc = MockDocumentReference();
    mockContactsCollection = MockCollectionReference();
    mockContactsSnapshot = MockQuerySnapshot();

    // Setup Auth
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockAuth.authStateChanges()).thenAnswer((_) => Stream.value(mockUser));
    when(() => mockUser.uid).thenReturn('test-user-id');

    // Setup Firestore Hierarchy
    when(() => mockFirestore.collection('users')).thenReturn(mockUsersCollection);
    when(() => mockUsersCollection.doc('test-user-id')).thenReturn(mockUserDoc);
    when(() => mockUserDoc.collection('contacts')).thenReturn(mockContactsCollection);

    // Mock snapshots for favorites listener in constructor
    final mockUserSnapshot = MockDocumentSnapshot();
    when(() => mockUserSnapshot.exists).thenReturn(false);
    when(() => mockUserDoc.snapshots()).thenAnswer((_) => Stream.value(mockUserSnapshot));
  });

  test('searchContacts performs batch queries correctly (N+1 optimization)', () async {
    // 1. Setup contacts data (15 contacts)
    final contactDocs = List.generate(15, (index) {
      final doc = MockQueryDocumentSnapshot();
      when(() => doc.id).thenReturn('contact-$index');
      return doc;
    });
    when(() => mockContactsSnapshot.docs).thenReturn(contactDocs);
    when(() => mockContactsCollection.get()).thenAnswer((_) async => mockContactsSnapshot);

    // 2. Setup batch queries
    final mockQuery = MockQuery();
    when(() => mockUsersCollection.where(any(), whereIn: any(named: 'whereIn')))
        .thenReturn(mockQuery);

    // Return a valid snapshot so processing continues
    final mockResultSnapshot = MockQuerySnapshot();
    when(() => mockResultSnapshot.docs).thenReturn([]); // Empty is fine for call count verification
    when(() => mockQuery.get()).thenAnswer((_) async => mockResultSnapshot);

    contactService = ContactService(firestore: mockFirestore, auth: mockAuth);

    await contactService.searchContacts('Contact');

    // Verification

    // 1. Verify fetching contact IDs (1 call)
    verify(() => mockContactsCollection.get()).called(1);

    // 2. Verify fetching user details (2 batch calls instead of 15)
    final captured = verify(() => mockUsersCollection.where(FieldPath.documentId, whereIn: captureAny(named: 'whereIn'))).captured;

    expect(captured.length, 2, reason: 'Should split 15 items into batches of 10 and 5');
    expect((captured[0] as List).length, 10);
    expect((captured[1] as List).length, 5);

    // 3. Verify NO individual document fetches occurred (proving N+1 is gone)
    // We check that collection('users').doc('contact-X') was never called.
    // Since mockUsersCollection is strict by default with mocktail (unless relaxed),
    // any unexpected call would actually throw during execution if not stubbed.
    // But we can also explicitly verify.
    verifyNever(() => mockUsersCollection.doc(any(that: startsWith('contact-'))));
  });
}
