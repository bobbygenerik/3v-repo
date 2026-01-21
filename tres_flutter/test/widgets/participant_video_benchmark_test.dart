import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:livekit_client/livekit_client.dart';

// Mocks
class MockRemoteTrackPublication extends Mock implements RemoteTrackPublication {}

void main() {
  test('Parallel subscription benchmark logic', () async {
    // Setup mocks
    final pubs = List.generate(10, (_) => MockRemoteTrackPublication());
    for (var p in pubs) {
      when(() => p.subscribed).thenReturn(false);
      // Simulate network delay
      when(() => p.subscribe()).thenAnswer((_) async => await Future.delayed(const Duration(milliseconds: 100)));
    }

    // Baseline: Sequential
    print('Starting Sequential Benchmark...');
    final stopwatchSeq = Stopwatch()..start();
    for (final pub in pubs) {
      if (!pub.subscribed) {
        await pub.subscribe();
      }
    }
    stopwatchSeq.stop();
    print('Sequential time: ${stopwatchSeq.elapsedMilliseconds}ms');

    // Optimization: Parallel
    print('Starting Parallel Benchmark...');
    final stopwatchPar = Stopwatch()..start();
    final futures = <Future>[];
    for (final pub in pubs) {
      if (!pub.subscribed) {
        futures.add(pub.subscribe());
      }
    }
    await Future.wait(futures);
    stopwatchPar.stop();
    print('Parallel time: ${stopwatchPar.elapsedMilliseconds}ms');

    // Expect significant improvement (parallel should be close to 100ms, sequential close to 1000ms)
    // We use a loose assertion to avoid flakiness, but check that it is at least 5x faster
    expect(stopwatchPar.elapsedMilliseconds, lessThan(stopwatchSeq.elapsedMilliseconds ~/ 5));
  });
}
