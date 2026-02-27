import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Benchmark sequential vs batch/parallel', () async {
    final stopwatch = Stopwatch();

    // Test sequential
    var fakeFirestore = FakeFirebaseFirestore();
    stopwatch.start();
    for (int i = 0; i < 200; i++) {
      final uid = 'contact-$i';
      await fakeFirestore.collection('users').doc('user1').collection('contacts').doc(uid).set(<String, dynamic>{});
      await fakeFirestore.collection('users').doc(uid).set(<String, dynamic>{'name': 'Contact $i'});
    }
    stopwatch.stop();
    print('Sequential time: ${stopwatch.elapsedMilliseconds}ms');

    // Test parallel
    fakeFirestore = FakeFirebaseFirestore();
    stopwatch.reset();
    stopwatch.start();
    final futures = <Future>[];
    for (int i = 0; i < 200; i++) {
      final uid = 'contact-$i';
      futures.add(fakeFirestore.collection('users').doc('user1').collection('contacts').doc(uid).set(<String, dynamic>{}));
      futures.add(fakeFirestore.collection('users').doc(uid).set(<String, dynamic>{'name': 'Contact $i'}));
    }
    await Future.wait(futures);
    stopwatch.stop();
    print('Parallel time: ${stopwatch.elapsedMilliseconds}ms');

    // Test batch
    fakeFirestore = FakeFirebaseFirestore();
    stopwatch.reset();
    stopwatch.start();
    final batch = fakeFirestore.batch();
    for (int i = 0; i < 200; i++) {
      final uid = 'contact-$i';
      batch.set(fakeFirestore.collection('users').doc('user1').collection('contacts').doc(uid), <String, dynamic>{});
      batch.set(fakeFirestore.collection('users').doc(uid), <String, dynamic>{'name': 'Contact $i'});
    }
    await batch.commit();
    stopwatch.stop();
    print('Batch time: ${stopwatch.elapsedMilliseconds}ms');
  });
}
