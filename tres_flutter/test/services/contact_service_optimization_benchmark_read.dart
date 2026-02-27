import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

void main() async {
  final fakeFirestore = FakeFirebaseFirestore();

  // Setup test data
  final batch = fakeFirestore.batch();
  final contactIds = <String>[];
  for (int i = 0; i < 200; i++) {
    contactIds.add('contact-$i');
    final ref1 = fakeFirestore
        .collection('users')
        .doc('test-user-id')
        .collection('contacts')
        .doc('contact-$i');
    batch.set(ref1, {'addedAt': DateTime.now()});

    final ref2 = fakeFirestore
        .collection('users')
        .doc('contact-$i');
    batch.set(ref2, {
      'displayName': 'Contact $i',
      'email': 'contact$i@example.com',
    });
  }
  await batch.commit();

  // Benchmark 1: Sequential Reads
  final stopwatch = Stopwatch()..start();
  final sequentialResults = [];
  for (final id in contactIds) {
    final doc = await fakeFirestore.collection('users').doc(id).get();
    sequentialResults.add(doc.data());
  }
  print('Sequential reads: ${stopwatch.elapsedMilliseconds}ms (${sequentialResults.length} docs)');

  // Benchmark 2: Batched (whereIn) Reads
  final stopwatch2 = Stopwatch()..start();
  final batchResults = [];
  const batchSize = 10;
  final futures = <Future<dynamic>>[];
  for (var i = 0; i < contactIds.length; i += batchSize) {
    final end = (i + batchSize < contactIds.length) ? i + batchSize : contactIds.length;
    final batchIds = contactIds.sublist(i, end);
    futures.add(fakeFirestore.collection('users').where('__name__', whereIn: batchIds).get());
  }
  final snapshots = await Future.wait(futures);
  for (final snapshot in snapshots) {
    for (final doc in snapshot.docs) {
      batchResults.add(doc.data());
    }
  }
  print('whereIn reads: ${stopwatch2.elapsedMilliseconds}ms (${batchResults.length} docs)');

  // Benchmark 3: Future.wait reads
  final stopwatch3 = Stopwatch()..start();
  final parallelResults = [];
  final readFutures = contactIds.map((id) => fakeFirestore.collection('users').doc(id).get()).toList();
  final readDocs = await Future.wait(readFutures);
  for (final doc in readDocs) {
    parallelResults.add(doc.data());
  }
  print('Future.wait reads: ${stopwatch3.elapsedMilliseconds}ms (${parallelResults.length} docs)');
}
