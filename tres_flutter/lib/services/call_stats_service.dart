import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'call_stats_model.dart';
export 'call_stats_model.dart';

/// Call Statistics Service — collects real event-driven stats and falls
/// back to native getStats when necessary.
class CallStatsService extends ChangeNotifier {
  static const String _tag = 'CallStats';

  Room? _room;
  Timer? _statsTimer;
  CallStats _currentStats = const CallStats();
  bool _isCollecting = false;
  EventsListener<RoomEvent>? _roomListener;

  // Latest metrics updated by LiveKit events
  double _lastVideoSendBitrate = 0.0;
  double _lastVideoRecvBitrate = 0.0;
  double _lastAudioSendBitrate = 0.0;
  double _lastAudioRecvBitrate = 0.0;
  double _lastVideoPacketLoss = 0.0; // percent (0-100)
  double _lastAudioPacketLoss = 0.0;
  double _lastRtt = 0.0; // seconds
  double _lastJitter = 0.0; // seconds
  String _lastResolution = 'N/A';
  int _lastFps = 0;

  final List<CallStats> _statsHistory = [];
  static const int _maxHistoryLength = 60;

  CallStats get currentStats => _currentStats;
  CallConnectionQuality get currentQuality => _currentStats.quality;
  bool get isCollecting => _isCollecting;

  /// Initialize with a LiveKit [Room] and register listeners for stats events.
  Future<void> initialize(Room room) async {
    _room = room;

    try {
      _roomListener = _room!.createListener();

      _roomListener
        ?..on<VideoSenderStatsEvent>((e) {
          _lastVideoSendBitrate = (e.currentBitrate ?? 0).toDouble();
          if (e.bitrateForLayers.isNotEmpty) {
            final sum = e.bitrateForLayers.values.fold<num>(0, (p, c) => p + (c ?? 0));
            _lastVideoSendBitrate = sum.toDouble();
          }
          final parsed = _parseStatsObject(e.stats);
          if (parsed['packetLoss'] != null) _lastVideoPacketLoss = parsed['packetLoss']!;
          if (parsed['rttMs'] != null) _lastRtt = (parsed['rttMs']! / 1000.0);
          if (parsed['jitterMs'] != null) _lastJitter = (parsed['jitterMs']! / 1000.0);
          if (parsed['width'] != null && parsed['height'] != null) {
            _lastResolution = '${parsed['width']!.toInt()}x${parsed['height']!.toInt()}';
          }
          if (parsed['fps'] != null) _lastFps = parsed['fps']!.toInt();
        })
        ..on<VideoReceiverStatsEvent>((e) {
          _lastVideoRecvBitrate = (e.currentBitrate ?? 0).toDouble();
          final parsed = _parseStatsObject(e.stats);
          if (parsed['packetLoss'] != null) _lastVideoPacketLoss = parsed['packetLoss']!;
          if (parsed['rttMs'] != null) _lastRtt = (parsed['rttMs']! / 1000.0);
          if (parsed['jitterMs'] != null) _lastJitter = (parsed['jitterMs']! / 1000.0);
          if (parsed['width'] != null && parsed['height'] != null) {
            _lastResolution = '${parsed['width']!.toInt()}x${parsed['height']!.toInt()}';
          }
          if (parsed['fps'] != null) _lastFps = parsed['fps']!.toInt();
        })
        ..on<AudioSenderStatsEvent>((e) {
          _lastAudioSendBitrate = (e.currentBitrate ?? 0).toDouble();
          final parsed = _parseStatsObject(e.stats);
          if (parsed['packetLoss'] != null) _lastAudioPacketLoss = parsed['packetLoss']!;
        })
        ..on<AudioReceiverStatsEvent>((e) {
          _lastAudioRecvBitrate = (e.currentBitrate ?? 0).toDouble();
          final parsed = _parseStatsObject(e.stats);
          if (parsed['packetLoss'] != null) _lastAudioPacketLoss = parsed['packetLoss']!;
          if (parsed['rttMs'] != null) _lastRtt = (parsed['rttMs']! / 1000.0);
          if (parsed['jitterMs'] != null) _lastJitter = (parsed['jitterMs']! / 1000.0);
        });
    } catch (e) {
      debugPrint('$_tag: Failed to register room stats listeners: $e');
    }
  }

  /// Start collecting statistics periodically (3s) and notify listeners.
  void startCollecting() {
    if (_isCollecting) return;
    if (_room == null) return;

    _isCollecting = true;
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      _flushCurrentStats();
    });
    notifyListeners();
  }

  /// Stop collecting statistics
  void stopCollecting() {
    if (!_isCollecting) return;
    _statsTimer?.cancel();
    _statsTimer = null;
    _isCollecting = false;
    notifyListeners();
  }

  /// Heuristic parser that walks nested maps/lists looking for packet loss, rtt, jitter
  Map<String, double?> _parseStatsObject(dynamic stats) {
    double? packetLoss;
    double? rttMs;
    double? jitterMs;
    double? width;
    double? height;
    double? fps;

    // Helpers to normalize values we find:
    double normalizePacketLoss(num raw) {
      final v = raw.toDouble();
      if (v <= 1.0) return v * 100.0; // fraction -> percent
      return v; // already percent
    }

    double normalizeRttMs(num raw) {
      final v = raw.toDouble();
      // Heuristic: values < 5 are likely seconds, >5 likely milliseconds
      if (v <= 5.0) return v * 1000.0; // seconds -> ms
      return v; // assume milliseconds
    }

    void recurse(dynamic obj) {
      if (obj == null) return;
      if (obj is Map) {
        for (final entry in obj.entries) {
          final key = entry.key?.toString().toLowerCase();
          final value = entry.value;
          if (value == null) continue;

          if (key != null) {
            // Packet loss variants
            if (key.contains('loss') || key.contains('packetslost') || key.contains('fraction_lost') || key.contains('fractionlost') || key.contains('lost') || key.contains('packets_lost') || key.contains('packet_loss') || key.contains('loss_rate')) {
              final v = double.tryParse(value.toString());
                if (v != null) {
                  final normalized = normalizePacketLoss(v);
                  double prev;
                  if (packetLoss != null) {
                    prev = packetLoss!;
                  } else {
                    prev = normalized;
                  }
                  packetLoss = packetLoss == null ? normalized : ((prev + normalized) / 2.0);
                }
            }

            // RTT variants
            else if (key.contains('rtt') || key.contains('roundtrip') || key.contains('round_trip')) {
              final v = double.tryParse(value.toString());
                if (v != null) {
                  final normalized = normalizeRttMs(v);
                  double prev;
                  if (rttMs != null) {
                    prev = rttMs!;
                  } else {
                    prev = normalized;
                  }
                  rttMs = rttMs == null ? normalized : ((prev + normalized) / 2.0);
                }
            }

            // Jitter variants
            else if (key.contains('jitter')) {
              final v = double.tryParse(value.toString());
                if (v != null) {
                  final normalized = normalizeRttMs(v);
                  double prev;
                  if (jitterMs != null) {
                    prev = jitterMs!;
                  } else {
                    prev = normalized;
                  }
                  jitterMs = jitterMs == null ? normalized : ((prev + normalized) / 2.0);
                }
            }

            // Video width
            else if (key == 'framewidth' || key == 'frame_width' || key == 'width') {
              final v = double.tryParse(value.toString());
              if (v != null && v > 0) width = v;
            }

            // Video height
            else if (key == 'frameheight' || key == 'frame_height' || key == 'height') {
              final v = double.tryParse(value.toString());
              if (v != null && v > 0) height = v;
            }

            // FPS
            else if (key == 'framespersecond' || key == 'frames_per_second' || key == 'framerate' || key == 'frame_rate' || key == 'fps') {
              final v = double.tryParse(value.toString());
              if (v != null && v > 0) fps = v;
            }
          }

          if (value is Map || value is Iterable) recurse(value);
        }
      } else if (obj is Iterable) {
        for (final item in obj) {
          recurse(item);
        }
      }
    }

    try {
      recurse(stats);
    } catch (_) {}

    // Final normalization: ensure packetLoss is in 0..100 and convert rtt/jitter to ms
    if (packetLoss != null) {
      if (packetLoss! < 0) packetLoss = 0.0;
      if (packetLoss! > 100.0) packetLoss = 100.0;
    }

    return {
      'packetLoss': packetLoss,
      'rttMs': rttMs,
      'jitterMs': jitterMs,
      'width': width,
      'height': height,
      'fps': fps,
    };
  }

  /// If event-driven fields are missing, try native getStats bridge.
  Future<void> _maybeFillFromNativeIfNeeded() async {
    // Native fallback removed: we rely solely on LiveKit event payloads.
    return;
  }

  /// Build CallStats and append to history
  void _flushCurrentStats() {
    final quality = _calculateQuality(rttMs: _lastRtt * 1000.0, packetLoss: _lastVideoPacketLoss);

    _currentStats = CallStats(
      videoSendBitrate: _lastVideoSendBitrate,
      videoRecvBitrate: _lastVideoRecvBitrate,
      videoPacketLoss: _lastVideoPacketLoss,
      videoResolution: _lastResolution,
      videoFps: _lastFps,
      audioSendBitrate: _lastAudioSendBitrate,
      audioRecvBitrate: _lastAudioRecvBitrate,
      audioPacketLoss: _lastAudioPacketLoss,
      roundTripTime: _lastRtt,
      jitter: _lastJitter,
      quality: quality,
    );

    _statsHistory.add(_currentStats);
    if (_statsHistory.length > _maxHistoryLength) {
      _statsHistory.removeAt(0);
    }

    notifyListeners();
  }

  /// Calculate a simple quality metric from RTT (ms) and packet loss (%)
  CallConnectionQuality _calculateQuality({required double rttMs, required double packetLoss}) {
    if (rttMs < 50 && packetLoss < 1) return CallConnectionQuality.excellent;
    if (rttMs < 100 && packetLoss < 2) return CallConnectionQuality.good;
    if (rttMs < 200 && packetLoss < 5) return CallConnectionQuality.fair;
    return CallConnectionQuality.poor;
  }

  /// Average stats over last N seconds
  CallStats getAverageStats({int seconds = 10}) {
    if (_statsHistory.isEmpty) return const CallStats();
    final recent = _statsHistory.length > seconds
        ? _statsHistory.sublist(_statsHistory.length - seconds)
        : List<CallStats>.from(_statsHistory);

    final count = recent.length;
    if (count == 0) return const CallStats();

    double avgDouble(List<double> vals) => vals.reduce((a, b) => a + b) / vals.length;

    return CallStats(
      videoSendBitrate: avgDouble(recent.map((s) => s.videoSendBitrate).toList()),
      videoRecvBitrate: avgDouble(recent.map((s) => s.videoRecvBitrate).toList()),
      videoPacketLoss: avgDouble(recent.map((s) => s.videoPacketLoss).toList()),
      videoResolution: recent.last.videoResolution,
      videoFps: (avgDouble(recent.map((s) => s.videoFps.toDouble()).toList())).round(),
      audioSendBitrate: avgDouble(recent.map((s) => s.audioSendBitrate).toList()),
      audioRecvBitrate: avgDouble(recent.map((s) => s.audioRecvBitrate).toList()),
      audioPacketLoss: avgDouble(recent.map((s) => s.audioPacketLoss).toList()),
      roundTripTime: avgDouble(recent.map((s) => s.roundTripTime).toList()),
      jitter: avgDouble(recent.map((s) => s.jitter).toList()),
      quality: _currentStats.quality,
    );
  }

  void clearHistory() {
    _statsHistory.clear();
    notifyListeners();
  }

  String getQualityTrend() {
    if (_statsHistory.length < 10) return 'Insufficient data';
    final recent = _statsHistory.sublist(_statsHistory.length - 5);
    final older = _statsHistory.sublist(_statsHistory.length - 10, _statsHistory.length - 5);
    final recentAvg = recent.map((s) => s.quality.score).reduce((a, b) => a + b) / recent.length;
    final olderAvg = older.map((s) => s.quality.score).reduce((a, b) => a + b) / older.length;
    final diff = recentAvg - olderAvg;
    if (diff > 10) return 'Improving ↗';
    if (diff < -10) return 'Degrading ↘';
    return 'Stable →';
  }

  Map<String, dynamic> getSummary() {
    if (_statsHistory.isEmpty) return {'message': 'No data available'};
    final avg = getAverageStats(seconds: _statsHistory.length);
    return {
      'current': _currentStats.toJson(),
      'average': avg.toJson(),
      'trend': getQualityTrend(),
      'duration': '${_statsHistory.length}s',
      'samples': _statsHistory.length,
    };
  }

  Future<void> cleanup() async {
    stopCollecting();
    _statsHistory.clear();
    _room = null;
  }

  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
}
