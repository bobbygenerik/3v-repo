import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  test('Call history fetching logic retrieves users correctly with batching', () async {
    final instance = FakeFirebaseFirestore();

    // Seed users
    // Creating 25 users to ensure we test multiple batches (10, 10, 5)
    for (int i = 0; i < 25; i++) {
      await instance.collection('users').doc('user_$i').set({
        'displayName': 'User $i',
        'email': 'user$i@example.com',
      });
    }

    // Simulate the set of IDs we need to fetch
    final Set<String> participantIdsToFetch = Set.from(
      List.generate(25, (i) => 'user_$i')
    );

    // The cache we want to populate
    final Map<String, Map<String, dynamic>> userCache = {};

    // Optimized logic implementation (simulating what will go into HomeScreen)
    final List<String> idsList = participantIdsToFetch.toList();

    for (var i = 0; i < idsList.length; i += 10) {
      final end = (i + 10 < idsList.length) ? i + 10 : idsList.length;
      final chunk = idsList.sublist(i, end);

      if (chunk.isEmpty) continue;

      try {
        final chunkSnapshot = await instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (var userDoc in chunkSnapshot.docs) {
          if (!userDoc.exists) continue;
          final userData = userDoc.data();
          // ignore: unnecessary_null_comparison
          if (userData != null) {
            userCache[userDoc.id] = userData;
          }
        }
      } catch (e) {
        // In a real app we might log this
        print('Error loading chunk: $e');
      }
    }

    // Assertions
    expect(userCache.length, 25, reason: 'Should have fetched all 25 users');

    // Check specific users
    expect(userCache['user_0']!['displayName'], 'User 0');
    expect(userCache['user_10']!['displayName'], 'User 10'); // Start of second batch
    expect(userCache['user_24']!['displayName'], 'User 24'); // Last user
  });
}
