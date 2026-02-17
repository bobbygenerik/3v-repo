import 'package:flutter_test/flutter_test.dart';
import 'dart:async';

// Mocking the structure of the data and firestore calls without full dependencies
// to keep the benchmark focused on the loop logic and async behavior.

class MockDocumentSnapshot {
  final String id;
  final Map<String, dynamic> _data;
  final bool exists;

  MockDocumentSnapshot(this.id, this._data, {this.exists = true});

  Map<String, dynamic> data() => _data;
}

class MockQuerySnapshot {
  final List<MockDocumentSnapshot> docs;
  MockQuerySnapshot(this.docs);
}

// Simulates the network delay
Future<MockQuerySnapshot> fetchChunk(List<String> chunkIds) async {
  // Simulate network latency of 50ms per batch request
  await Future.delayed(const Duration(milliseconds: 50));

  return MockQuerySnapshot(
    chunkIds.map((id) => MockDocumentSnapshot(id, {
      'displayName': 'User $id',
      'email': 'user$id@example.com',
      'photoURL': null,
    })).toList()
  );
}

void main() {
  test('Benchmark: Sequential vs Parallel Contact Loading', () async {
    // Setup test data
    final int totalContacts = 100;
    final List<String> contactIds = List.generate(totalContacts, (index) => 'user_$index');

    // --- Baseline: Sequential Loading ---
    final stopwatchSequential = Stopwatch()..start();
    final Map<String, Map<String, dynamic>> contactsMapSequential = {};

    print('Starting Sequential Loading...');
    for (var i = 0; i < contactIds.length; i += 10) {
      final end = (i + 10 < contactIds.length) ? i + 10 : contactIds.length;
      final chunk = contactIds.sublist(i, end);

      if (chunk.isEmpty) continue;

      try {
        final chunkSnapshot = await fetchChunk(chunk);

        for (var userDoc in chunkSnapshot.docs) {
          if (!userDoc.exists) continue;
          final data = userDoc.data();
          final contactUid = userDoc.id;

          contactsMapSequential[contactUid] = {
            'uid': contactUid,
            'name': data['displayName'] ?? 'Unknown',
            'email': data['email'] ?? '',
            'photoURL': data['photoURL'],
          };
        }
      } catch (e) {
        print('Error loading contact chunk: $e');
      }
    }
    stopwatchSequential.stop();
    print('Sequential Loading took: ${stopwatchSequential.elapsedMilliseconds}ms');

    // --- Optimization: Parallel Loading ---
    final stopwatchParallel = Stopwatch()..start();
    final Map<String, Map<String, dynamic>> contactsMapParallel = {};

    print('Starting Parallel Loading...');

    final List<Future<void>> futures = [];

    for (var i = 0; i < contactIds.length; i += 10) {
      final end = (i + 10 < contactIds.length) ? i + 10 : contactIds.length;
      final chunk = contactIds.sublist(i, end);

      if (chunk.isEmpty) continue;

      // Add the future to the list instead of awaiting it immediately
      futures.add(() async {
        try {
          final chunkSnapshot = await fetchChunk(chunk);

          for (var userDoc in chunkSnapshot.docs) {
            if (!userDoc.exists) continue;
            final data = userDoc.data();
            final contactUid = userDoc.id;

            // Note: In a real app, ensure map access is thread-safe if necessary,
            // though Dart is single-threaded event loop so simple assignment is fine.
            contactsMapParallel[contactUid] = {
              'uid': contactUid,
              'name': data['displayName'] ?? 'Unknown',
              'email': data['email'] ?? '',
              'photoURL': data['photoURL'],
            };
          }
        } catch (e) {
          print('Error loading contact chunk: $e');
        }
      }());
    }

    await Future.wait(futures);

    stopwatchParallel.stop();
    print('Parallel Loading took: ${stopwatchParallel.elapsedMilliseconds}ms');

    // --- Verification ---
    expect(contactsMapParallel.length, totalContacts);
    expect(contactsMapSequential.length, totalContacts);

    // Check that data matches
    for (final id in contactIds) {
      expect(contactsMapParallel[id], equals(contactsMapSequential[id]));
    }

    print('Speedup: ${(stopwatchSequential.elapsedMilliseconds / stopwatchParallel.elapsedMilliseconds).toStringAsFixed(2)}x');
  });
}
