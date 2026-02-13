import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tres_flutter/services/user_lookup_service.dart';
import 'package:tres_flutter/firebase_options.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}
class MockCollectionReference extends Mock implements CollectionReference<Map<String, dynamic>> {}
class MockDocumentReference extends Mock implements DocumentReference<Map<String, dynamic>> {}
class MockQuery extends Mock implements Query<Map<String, dynamic>> {}
class MockQuerySnapshot extends Mock implements QuerySnapshot<Map<String, dynamic>> {}
class MockQueryDocumentSnapshot extends Mock implements QueryDocumentSnapshot<Map<String, dynamic>> {}
class MockDocumentSnapshot extends Mock implements DocumentSnapshot<Map<String, dynamic>> {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserLookupService service;
  late MockFirebaseFirestore mockFirestore;
  late MockCollectionReference mockUsersCollection;

  // Setup Firebase mocks
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

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockUsersCollection = MockCollectionReference();

    service = UserLookupService();
    service.firestore = mockFirestore;
    service.clearCache();

    when(() => mockFirestore.collection('users')).thenReturn(mockUsersCollection);
  });

  test('fetchForIdentity uses batched queries (Optimized O(N/10))', () async {
    // Prepare results for Email batch
    final emailQuery = MockQuery();
    final emailQuerySnap = MockQuerySnapshot();
    final emailDocs = <MockQueryDocumentSnapshot>[];
    for (int i = 0; i < 10; i++) {
       final d = MockQueryDocumentSnapshot();
       // Note: implementation queries by lowercase email
       when(() => d.data()).thenReturn({'email': 'user$i@example.com', 'displayName': 'Email User $i', 'photoURL': ''});
       emailDocs.add(d);
    }
    when(() => emailQuerySnap.docs).thenReturn(emailDocs);
    when(() => emailQuery.get()).thenAnswer((_) async => emailQuerySnap);

    // Prepare results for UID batch
    final uidQuery = MockQuery();
    final uidQuerySnap = MockQuerySnapshot();
    final uidDocs = <MockQueryDocumentSnapshot>[];
    for (int i = 0; i < 10; i++) {
       final d = MockQueryDocumentSnapshot();
       when(() => d.id).thenReturn('user_$i');
       when(() => d.data()).thenReturn({'displayName': 'User $i', 'photoURL': ''});
       uidDocs.add(d);
    }
    when(() => uidQuerySnap.docs).thenReturn(uidDocs);
    when(() => uidQuery.get()).thenAnswer((_) async => uidQuerySnap);

    // Mock where calls
    // We expect 'email' queries
    when(() => mockUsersCollection.where('email', whereIn: any(named: 'whereIn')))
      .thenReturn(emailQuery);

    // We expect documentId queries
    when(() => mockUsersCollection.where(FieldPath.documentId, whereIn: any(named: 'whereIn')))
      .thenReturn(uidQuery);

    final futures = <Future<Map<String, String>>>[];

    // Launch 10 ID lookups
    for (int i = 0; i < 10; i++) {
      futures.add(service.fetchForIdentity('user_$i'));
    }
    // Launch 10 Email lookups
    for (int i = 0; i < 10; i++) {
      futures.add(service.fetchForIdentity('user$i@example.com'));
    }

    // Await all results
    final results = await Future.wait(futures);

    // Verify correct data returned
    // First 10 are UIDs
    for (int i = 0; i < 10; i++) {
      expect(results[i]['displayName'], 'User $i');
    }
    // Next 10 are Emails
    for (int i = 0; i < 10; i++) {
      expect(results[10 + i]['displayName'], 'Email User $i');
    }

    // Verify optimized calls:
    // Should NOT call doc(id).get()
    verifyNever(() => mockUsersCollection.doc(any()));

    // Should call where('email', whereIn: ...) once (since 10 items fit in one batch)
    verify(() => mockUsersCollection.where('email', whereIn: any(named: 'whereIn'))).called(1);

    // Should call where(FieldPath.documentId, whereIn: ...) once
    verify(() => mockUsersCollection.where(FieldPath.documentId, whereIn: any(named: 'whereIn'))).called(1);

    // If we want to be stricter, we can capture the arguments.
  });
}
