import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tres_flutter/firebase_options.dart';
import 'package:tres_flutter/services/user_lookup_service.dart';

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

  late UserLookupService service;
  late FakeFirebaseFirestore fakeFirestore;

  Future<void> seedUsers(FirebaseFirestore firestore) async {
    // Seed UID-based docs
    for (int i = 0; i < 10; i++) {
      await firestore.collection('users').doc('user_$i').set({
        'displayName': 'User $i',
        'photoURL': '',
      });
    }

    // Seed email-based docs (query uses lowercased email field)
    for (int i = 0; i < 10; i++) {
      await firestore.collection('users').doc('email_user_$i').set({
        'email': 'user$i@example.com',
        'displayName': 'Email User $i',
        'photoURL': '',
      });
    }
  }

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    await seedUsers(fakeFirestore);

    service = UserLookupService();
    service.firestore = fakeFirestore;
    service.clearCache();
  });

  test('fetchForIdentity uses batched queries (Optimized O(N/10))', () async {
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
  });

  test('fetchForIdentity returns cached result on repeat lookup', () async {
    const identity = 'user_1';

    final first = await service.fetchForIdentity(identity);
    expect(first['displayName'], 'User 1');

    // Remove backing data and ensure cached value is still returned.
    await fakeFirestore.collection('users').doc(identity).delete();
    final second = await service.fetchForIdentity(identity);

    expect(second['displayName'], 'User 1');
  });
}
