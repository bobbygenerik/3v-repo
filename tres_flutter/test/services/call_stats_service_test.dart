import 'package:flutter_test/flutter_test.dart';
import 'package:tres_flutter/services/call_stats_service.dart';

void main() {
  test('Benchmark parseStatsObject', () {
    // Construct a large stats object
    final Map<String, dynamic> largeStats = {};
    for (int i = 0; i < 1000; i++) {
      largeStats['report_$i'] = {
        'id': 'report_$i',
        'timestamp': 1234567890,
        'type': 'inbound-rtp',
        'packetsLost': i % 100,
        'roundTripTime': (i % 50) / 1000.0,
        'jitter': 0.03,
        'nested': {
          'more_data': List.generate(
            10,
            (j) => {'value': j, 'width': 1920, 'height': 1080, 'fps': 30},
          ),
        },
      };
    }

    final stopwatch = Stopwatch()..start();
    for (int i = 0; i < 100; i++) {
      parseStatsObject(largeStats);
    }
    stopwatch.stop();

    print('Time taken for 100 iterations: ${stopwatch.elapsedMilliseconds} ms');
    print(
      'Average time per iteration: ${stopwatch.elapsedMilliseconds / 100} ms',
    );
  });

  test('parseStatsObject functionality', () {
    final stats = {
      'rtp': {
        'packetsLost': 10,
        'roundTripTime': 0.05, // 50ms
        'jitter': 0.01, // 10ms
      },
      'video': {
        'width': 1920,
        'height': 1080,
        'framesPerSecond': 30,
        'availableOutgoingBitrate': 1000000,
      },
    };

    final result = parseStatsObject(stats);
    expect(result['packetLoss'], 10.0);
    expect(result['rttMs'], 50.0);
    expect(result['jitterMs'], 10.0);
    expect(result['width'], 1920.0);
    expect(result['height'], 1080.0);
    expect(result['fps'], 30.0);
    expect(result['availableOutgoingBitrate'], 1000000.0);
  });
}
