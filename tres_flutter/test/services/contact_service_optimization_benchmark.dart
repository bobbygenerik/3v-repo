import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

void main() async {
  final fakeFirestore = FakeFirebaseFirestore();

  final stopwatch = Stopwatch()..start();

  for (int i = 0; i < 200; i++) {
    await fakeFirestore
        .collection('users')
        .doc('test-user-id')
        .collection('contacts')
        .doc('contact-$i')
        .set({'addedAt': DateTime.now()});

    await fakeFirestore
        .collection('users')
        .doc('contact-$i')
        .set({
      'displayName': 'Contact $i',
      'email': 'contact$i@example.com',
    });
  }

  print('Sequential writes: ${stopwatch.elapsedMilliseconds}ms');

  final fakeFirestore2 = FakeFirebaseFirestore();
  final stopwatch2 = Stopwatch()..start();

  final batch = fakeFirestore2.batch();
  for (int i = 0; i < 200; i++) {
    final ref1 = fakeFirestore2
        .collection('users')
        .doc('test-user-id-2')
        .collection('contacts')
        .doc('contact-$i');
    batch.set(ref1, {'addedAt': DateTime.now()});

    final ref2 = fakeFirestore2
        .collection('users')
        .doc('contact-$i');
    batch.set(ref2, {
      'displayName': 'Contact $i',
      'email': 'contact$i@example.com',
    });
  }
  await batch.commit();

  print('Batched writes: ${stopwatch2.elapsedMilliseconds}ms');


  final fakeFirestore3 = FakeFirebaseFirestore();
  final stopwatch3 = Stopwatch()..start();

  final futures = <Future>[];
  for (int i = 0; i < 200; i++) {
    futures.add(fakeFirestore3
        .collection('users')
        .doc('test-user-id-3')
        .collection('contacts')
        .doc('contact-$i')
        .set({'addedAt': DateTime.now()}));

    futures.add(fakeFirestore3
        .collection('users')
        .doc('contact-$i')
        .set({
      'displayName': 'Contact $i',
      'email': 'contact$i@example.com',
    }));
  }
  await Future.wait(futures);

  print('Future.wait writes: ${stopwatch3.elapsedMilliseconds}ms');
}
