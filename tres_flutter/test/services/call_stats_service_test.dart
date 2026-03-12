import 'package:flutter_test/flutter_test.dart';

Map<String, double?> parseStatsObject(dynamic stats) {
  double? packetLoss;
  double? rttMs;
  double? jitterMs;
  double? width;
  double? height;
  double? fps;
  double? availableOutgoingBitrate;

  double normalizePacketLoss(num raw) {
    final value = raw.toDouble();
    return value <= 1.0 ? value * 100.0 : value;
  }

  double normalizeRttMs(num raw) {
    final value = raw.toDouble();
    return value <= 5.0 ? value * 1000.0 : value;
  }

  void recurse(dynamic obj) {
    if (obj == null) return;

    if (obj is Map) {
      for (final entry in obj.entries) {
        final key = entry.key?.toString().toLowerCase();
        final value = entry.value;
        if (key == null || value == null) {
          if (value is Map || value is Iterable) recurse(value);
          continue;
        }

        if (key.contains('loss') ||
            key.contains('packetslost') ||
            key.contains('fraction_lost') ||
            key.contains('fractionlost') ||
            key.contains('lost') ||
            key.contains('packets_lost') ||
            key.contains('packet_loss') ||
            key.contains('loss_rate')) {
          final parsed = double.tryParse(value.toString());
          if (parsed != null) {
            final normalized = normalizePacketLoss(parsed);
            packetLoss = packetLoss == null
                ? normalized
                : ((packetLoss! + normalized) / 2.0);
          }
        } else if (key.contains('rtt') ||
            key.contains('roundtrip') ||
            key.contains('round_trip')) {
          final parsed = double.tryParse(value.toString());
          if (parsed != null) {
            final normalized = normalizeRttMs(parsed);
            rttMs = rttMs == null ? normalized : ((rttMs! + normalized) / 2.0);
          }
        } else if (key.contains('jitter')) {
          final parsed = double.tryParse(value.toString());
          if (parsed != null) {
            final normalized = normalizeRttMs(parsed);
            jitterMs =
                jitterMs == null ? normalized : ((jitterMs! + normalized) / 2.0);
          }
        } else if (key.contains('availableoutgoingbitrate') ||
            key.contains('available_outgoing_bitrate')) {
          final parsed = double.tryParse(value.toString());
          if (parsed != null && parsed > 0) {
            availableOutgoingBitrate = parsed;
          }
        } else if (key == 'framewidth' || key == 'frame_width' || key == 'width') {
          final parsed = double.tryParse(value.toString());
          if (parsed != null && parsed > 0) width = parsed;
        } else if (key == 'frameheight' || key == 'frame_height' || key == 'height') {
          final parsed = double.tryParse(value.toString());
          if (parsed != null && parsed > 0) height = parsed;
        } else if (key == 'framespersecond' ||
            key == 'frames_per_second' ||
            key == 'framerate' ||
            key == 'frame_rate' ||
            key == 'fps') {
          final parsed = double.tryParse(value.toString());
          if (parsed != null && parsed > 0) fps = parsed;
        }

        if (value is Map || value is Iterable) recurse(value);
      }
    } else if (obj is Iterable) {
      for (final value in obj) {
        recurse(value);
      }
    }
  }

  recurse(stats);

  return {
    'packetLoss': packetLoss,
    'rttMs': rttMs,
    'jitterMs': jitterMs,
    'availableOutgoingBitrate': availableOutgoingBitrate,
    'width': width,
    'height': height,
    'fps': fps,
  };
}

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
           'more_data': List.generate(10, (j) => {'value': j, 'width': 1920, 'height': 1080, 'fps': 30}),
        }
      };
    }

    final stopwatch = Stopwatch()..start();
    for (int i = 0; i < 100; i++) {
      parseStatsObject(largeStats);
    }
    stopwatch.stop();

    print('Time taken for 100 iterations: ${stopwatch.elapsedMilliseconds} ms');
    print('Average time per iteration: ${stopwatch.elapsedMilliseconds / 100} ms');
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
      }
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
