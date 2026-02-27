import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

void main() {
  test('Benchmark: Sequential vs Batch Inserts', () async {
    final sequentialInstance = FakeFirebaseFirestore();
    final batchInstance = FakeFirebaseFirestore();
    final numRecords = 25;

    final sequentialStopwatch = Stopwatch()..start();
    for (int i = 0; i < numRecords; i++) {
      await sequentialInstance.collection('users_seq').doc('user_$i').set({
        'displayName': 'User $i',
        'email': 'user$i@example.com',
      });
    }
    sequentialStopwatch.stop();

    final batchStopwatch = Stopwatch()..start();
    final batch = batchInstance.batch();
    for (int i = 0; i < numRecords; i++) {
      final docRef = batchInstance.collection('users_batch').doc('user_$i');
      batch.set(docRef, {
        'displayName': 'User $i',
        'email': 'user$i@example.com',
      });
    }
    await batch.commit();
    batchStopwatch.stop();

    print(
      'Sequential inserts ($numRecords records): ${sequentialStopwatch.elapsedMilliseconds} ms',
    );
    print(
      'Batch inserts ($numRecords records): ${batchStopwatch.elapsedMilliseconds} ms',
    );
  });
}
