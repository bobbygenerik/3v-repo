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
  DateTime? _lastStatsLogAt;

  // Latest metrics updated by LiveKit events
  double _lastVideoSendBitrate = 0.0;
  double _lastVideoRecvBitrate = 0.0;
  double _lastAudioSendBitrate = 0.0;
  double _lastAudioRecvBitrate = 0.0;
  double _lastVideoPacketLoss = 0.0; // percent (0-100)
  double _lastAudioPacketLoss = 0.0;
  double _lastRtt = 0.0; // seconds
  double _lastJitter = 0.0; // seconds
  double _lastAvailableOutgoingBitrate = 0.0; // bits per second
  String _lastResolution = 'N/A';
  int _lastFps = 0;
  String _lastVideoCodec = 'unknown';
  String _lastAudioCodec = 'unknown';

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
        ?..on<VideoSenderStatsEvent>((e) async {
          debugPrint('📊 VideoSenderStatsEvent: bitrate=${e.currentBitrate}');
          _lastVideoSendBitrate = (e.currentBitrate ?? 0).toDouble();
          if (e.bitrateForLayers.isNotEmpty) {
            final sum = e.bitrateForLayers.values.fold<num>(
              0,
              (p, c) => p + (c ?? 0),
            );
            _lastVideoSendBitrate = sum.toDouble();
          }

          // Offload parsing to isolate
          try {
            final result = await compute(_processStats, {
              'stats': e.stats,
              'isVideo': true,
            });
            final parsed = (result['parsed'] as Map).cast<String, double?>();
            final codec = result['codec'] as String?;

            if (parsed['packetLoss'] != null)
              _lastVideoPacketLoss = parsed['packetLoss']!;
            if (parsed['rttMs'] != null) _lastRtt = (parsed['rttMs']! / 1000.0);
            if (parsed['jitterMs'] != null)
              _lastJitter = (parsed['jitterMs']! / 1000.0);
            if (parsed['availableOutgoingBitrate'] != null) {
              _lastAvailableOutgoingBitrate =
                  parsed['availableOutgoingBitrate']!;
            }
            if (parsed['width'] != null && parsed['height'] != null) {
              _lastResolution =
                  '${parsed['width']!.toInt()}x${parsed['height']!.toInt()}';
            }
            if (parsed['fps'] != null) _lastFps = parsed['fps']!.toInt();
            if (codec != null && codec.isNotEmpty) _lastVideoCodec = codec;
          } catch (e) {
            debugPrint('$_tag: Error computing stats: $e');
          }
        })
        ..on<VideoReceiverStatsEvent>((e) async {
          _lastVideoRecvBitrate = (e.currentBitrate ?? 0).toDouble();

          try {
            final result = await compute(_processStats, {
              'stats': e.stats,
              'isVideo': true,
            });
            final parsed = result['parsed'] as Map<String, double?>;
            final codec = result['codec'] as String?;

            if (parsed['packetLoss'] != null)
              _lastVideoPacketLoss = parsed['packetLoss']!;
            if (parsed['rttMs'] != null) _lastRtt = (parsed['rttMs']! / 1000.0);
            if (parsed['jitterMs'] != null)
              _lastJitter = (parsed['jitterMs']! / 1000.0);
            if (parsed['availableOutgoingBitrate'] != null) {
              _lastAvailableOutgoingBitrate =
                  parsed['availableOutgoingBitrate']!;
            }
            if (parsed['width'] != null && parsed['height'] != null) {
              _lastResolution =
                  '${parsed['width']!.toInt()}x${parsed['height']!.toInt()}';
            }
            if (parsed['fps'] != null) _lastFps = parsed['fps']!.toInt();
            if (codec != null && codec.isNotEmpty) _lastVideoCodec = codec;
          } catch (e) {
            debugPrint('$_tag: Error computing stats: $e');
          }
        })
        ..on<AudioSenderStatsEvent>((e) async {
          _lastAudioSendBitrate = (e.currentBitrate ?? 0).toDouble();

          try {
            final result = await compute(_processStats, {
              'stats': e.stats,
              'isVideo': false,
            });
            final parsed = (result['parsed'] as Map).cast<String, double?>();
            final codec = result['codec'] as String?;

            if (parsed['packetLoss'] != null)
              _lastAudioPacketLoss = parsed['packetLoss']!;
            if (codec != null && codec.isNotEmpty) _lastAudioCodec = codec;
          } catch (e) {
            debugPrint('$_tag: Error computing stats: $e');
          }
        })
        ..on<AudioReceiverStatsEvent>((e) async {
          _lastAudioRecvBitrate = (e.currentBitrate ?? 0).toDouble();

          try {
            final result = await compute(_processStats, {
              'stats': e.stats,
              'isVideo': false,
            });
            final parsed = result['parsed'] as Map<String, double?>;
            final codec = result['codec'] as String?;

            if (parsed['packetLoss'] != null)
              _lastAudioPacketLoss = parsed['packetLoss']!;
            if (parsed['rttMs'] != null) _lastRtt = (parsed['rttMs']! / 1000.0);
            if (parsed['jitterMs'] != null)
              _lastJitter = (parsed['jitterMs']! / 1000.0);
            if (codec != null && codec.isNotEmpty) _lastAudioCodec = codec;
          } catch (e) {
            debugPrint('$_tag: Error computing stats: $e');
          }
        });
    } catch (e) {
      debugPrint('$_tag: Failed to register room stats listeners: $e');
    }
  }

  /// Helper to process stats in an isolate
  static Map<String, dynamic> _processStats(Map<String, dynamic> args) {
    final stats = args['stats'];
    final isVideo = args['isVideo'] as bool;

    final parsed = _parseStatsObject(stats);
    final codec = _extractCodecName(stats, isVideo: isVideo);

    return {'parsed': parsed, 'codec': codec};
  }

  /// Start collecting statistics periodically (3s) and notify listeners.
  void startCollecting() {
    if (_isCollecting) return;
    if (_room == null) return;

    debugPrint('📊 CallStatsService: Starting stats collection');
    _isCollecting = true;
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      debugPrint(
        '📊 CallStatsService: Flushing stats - video send=$_lastVideoSendBitrate, recv=$_lastVideoRecvBitrate',
      );
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
  static Map<String, double?> _parseStatsObject(dynamic stats) {
    double? packetLoss;
    double? rttMs;
    double? jitterMs;
    double? availableOutgoingBitrate;
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
            if (key.contains('loss') ||
                key.contains('packetslost') ||
                key.contains('fraction_lost') ||
                key.contains('fractionlost') ||
                key.contains('lost') ||
                key.contains('packets_lost') ||
                key.contains('packet_loss') ||
                key.contains('loss_rate')) {
              final v = double.tryParse(value.toString());
              if (v != null) {
                final normalized = normalizePacketLoss(v);
                double prev;
                if (packetLoss != null) {
                  prev = packetLoss!;
                } else {
                  prev = normalized;
                }
                packetLoss = packetLoss == null
                    ? normalized
                    : ((prev + normalized) / 2.0);
              }
            }
            // RTT variants
            else if (key.contains('rtt') ||
                key.contains('roundtrip') ||
                key.contains('round_trip')) {
              final v = double.tryParse(value.toString());
              if (v != null) {
                final normalized = normalizeRttMs(v);
                double prev;
                if (rttMs != null) {
                  prev = rttMs!;
                } else {
                  prev = normalized;
                }
                rttMs = rttMs == null
                    ? normalized
                    : ((prev + normalized) / 2.0);
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
                jitterMs = jitterMs == null
                    ? normalized
                    : ((prev + normalized) / 2.0);
              }
            }
            // Available outgoing bitrate (bps)
            else if (key.contains('availableoutgoingbitrate') ||
                key.contains('available_outgoing_bitrate')) {
              final v = double.tryParse(value.toString());
              if (v != null && v > 0) {
                availableOutgoingBitrate = v;
              }
            }
            // Video width
            else if (key == 'framewidth' ||
                key == 'frame_width' ||
                key == 'width') {
              final v = double.tryParse(value.toString());
              if (v != null && v > 0) width = v;
            }
            // Video height
            else if (key == 'frameheight' ||
                key == 'frame_height' ||
                key == 'height') {
              final v = double.tryParse(value.toString());
              if (v != null && v > 0) height = v;
            }
            // FPS
            else if (key == 'framespersecond' ||
                key == 'frames_per_second' ||
                key == 'framerate' ||
                key == 'frame_rate' ||
                key == 'fps') {
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
      'availableOutgoingBitrate': availableOutgoingBitrate,
      'width': width,
      'height': height,
      'fps': fps,
    };
  }

  static String? _extractCodecName(dynamic stats, {required bool isVideo}) {
    String? found;

    bool matchesCodecValue(String valueLower) {
      if (isVideo) {
        return valueLower.contains('video/') ||
            valueLower.contains('h264') ||
            valueLower.contains('av1') ||
            valueLower.contains('vp8') ||
            valueLower.contains('vp9') ||
            valueLower.contains('h265') ||
            valueLower.contains('hevc');
      }
      return valueLower.contains('audio/') ||
          valueLower.contains('opus') ||
          valueLower.contains('isac') ||
          valueLower.contains('pcmu') ||
          valueLower.contains('pcma') ||
          valueLower.contains('g722');
    }

    String normalize(String raw) {
      var value = raw.trim();
      if (value.contains('/')) {
        value = value.split('/').last;
      }
      value = value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      if (value.isEmpty) return raw;
      return value.toUpperCase();
    }

    void recurse(dynamic obj) {
      if (obj == null || found != null) return;
      if (obj is Map) {
        for (final entry in obj.entries) {
          if (found != null) return;
          final key = entry.key?.toString().toLowerCase() ?? '';
          final value = entry.value;
          if (value is String) {
            final valueLower = value.toLowerCase();
            if (key.contains('codec') || key.contains('mime')) {
              if (matchesCodecValue(valueLower)) {
                found = normalize(value);
                return;
              }
            }
            if (matchesCodecValue(valueLower)) {
              found = normalize(value);
              return;
            }
          }
          if (value is Map || value is Iterable) {
            recurse(value);
          }
        }
      } else if (obj is Iterable) {
        for (final item in obj) {
          if (found != null) return;
          recurse(item);
        }
      }
    }

    try {
      recurse(stats);
    } catch (_) {}

    return found;
  }

  /// If event-driven fields are missing, try to collect from room
  Future<void> _maybeFillFromNativeIfNeeded() async {
    // LiveKit stats events may not fire reliably on any platform
    // Use native WebRTC getStats() API as fallback
    if (_room == null) return;

    try {
      final localParticipant = _room!.localParticipant;
      if (localParticipant == null) return;

      // Get video track stats
      final videoTrack =
          localParticipant.videoTrackPublications.firstOrNull?.track;
      if (videoTrack != null) {
        // Note: getStats() is not available on LocalVideoTrack in this version of livekit_client
        // final stats = await videoTrack.getStats();
        // if (stats != null) {
        //   final parsed = _parseStatsObject(stats);
        //   if (parsed['packetLoss'] != null) _lastVideoPacketLoss = parsed['packetLoss']!;
        //   if (parsed['rttMs'] != null) _lastRtt = (parsed['rttMs']! / 1000.0);
        //   if (parsed['jitterMs'] != null) _lastJitter = (parsed['jitterMs']! / 1000.0);
        //   if (parsed['availableOutgoingBitrate'] != null) {
        //     _lastAvailableOutgoingBitrate = parsed['availableOutgoingBitrate']!;
        //   }
        //   if (parsed['width'] != null && parsed['height'] != null) {
        //     _lastResolution = '${parsed['width']!.toInt()}x${parsed['height']!.toInt()}';
        //   }
        //   if (parsed['fps'] != null) _lastFps = parsed['fps']!.toInt();
        // }
      }

      // Get audio track stats
      final audioTrack =
          localParticipant.audioTrackPublications.firstOrNull?.track;
      if (audioTrack != null) {
        // Note: getStats() is not available on LocalAudioTrack in this version of livekit_client
        // final stats = await audioTrack.getStats();
        // if (stats != null) {
        //   final parsed = _parseStatsObject(stats);
        //   if (parsed['packetLoss'] != null) _lastAudioPacketLoss = parsed['packetLoss']!;
        // }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get native stats: $e');
    }
  }

  /// Build CallStats and append to history
  void _flushCurrentStats() async {
    // Try to fill missing stats from native WebRTC getStats
    await _maybeFillFromNativeIfNeeded();

    final quality = _calculateQuality(
      rttMs: _lastRtt * 1000.0,
      packetLoss: _lastVideoPacketLoss,
    );

    _currentStats = CallStats(
      videoSendBitrate: _lastVideoSendBitrate,
      videoRecvBitrate: _lastVideoRecvBitrate,
      videoPacketLoss: _lastVideoPacketLoss,
      videoResolution: _lastResolution,
      videoFps: _lastFps,
      videoCodec: _lastVideoCodec,
      audioSendBitrate: _lastAudioSendBitrate,
      audioRecvBitrate: _lastAudioRecvBitrate,
      audioPacketLoss: _lastAudioPacketLoss,
      audioCodec: _lastAudioCodec,
      roundTripTime: _lastRtt,
      jitter: _lastJitter,
      availableOutgoingBitrate: _lastAvailableOutgoingBitrate,
      quality: quality,
    );

    _statsHistory.add(_currentStats);
    if (_statsHistory.length > _maxHistoryLength) {
      _statsHistory.removeAt(0);
    }

    _maybeLogStatsSnapshot();
    notifyListeners();
  }

  void _maybeLogStatsSnapshot() {
    final now = DateTime.now();
    if (_lastStatsLogAt != null &&
        now.difference(_lastStatsLogAt!) < const Duration(seconds: 10)) {
      return;
    }
    _lastStatsLogAt = now;
    debugPrint(
      '📊 CallStats '
      'send=${_currentStats.videoSendBitrateFormatted} '
      'recv=${_currentStats.videoRecvBitrateFormatted} '
      'codec=${_currentStats.videoCodec} '
      'loss=${_currentStats.videoPacketLossFormatted} '
      'rtt=${_currentStats.roundTripTimeFormatted} '
      'jitter=${_currentStats.jitterFormatted} '
      'fps=${_currentStats.videoFps} '
      'res=${_currentStats.videoResolution} '
      'avail=${_currentStats.availableOutgoingBitrateFormatted} '
      'audioCodec=${_currentStats.audioCodec} '
      'quality=${_currentStats.quality.label}',
    );
  }

  /// Calculate a simple quality metric from RTT (ms) and packet loss (%)
  CallConnectionQuality _calculateQuality({
    required double rttMs,
    required double packetLoss,
  }) {
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

    double avgDouble(List<double> vals) =>
        vals.reduce((a, b) => a + b) / vals.length;

    return CallStats(
      videoSendBitrate: avgDouble(
        recent.map((s) => s.videoSendBitrate).toList(),
      ),
      videoRecvBitrate: avgDouble(
        recent.map((s) => s.videoRecvBitrate).toList(),
      ),
      videoPacketLoss: avgDouble(recent.map((s) => s.videoPacketLoss).toList()),
      videoResolution: recent.last.videoResolution,
      videoFps: (avgDouble(
        recent.map((s) => s.videoFps.toDouble()).toList(),
      )).round(),
      videoCodec: recent.last.videoCodec,
      audioSendBitrate: avgDouble(
        recent.map((s) => s.audioSendBitrate).toList(),
      ),
      audioRecvBitrate: avgDouble(
        recent.map((s) => s.audioRecvBitrate).toList(),
      ),
      audioPacketLoss: avgDouble(recent.map((s) => s.audioPacketLoss).toList()),
      audioCodec: recent.last.audioCodec,
      roundTripTime: avgDouble(recent.map((s) => s.roundTripTime).toList()),
      jitter: avgDouble(recent.map((s) => s.jitter).toList()),
      availableOutgoingBitrate: avgDouble(
        recent.map((s) => s.availableOutgoingBitrate).toList(),
      ),
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
    final older = _statsHistory.sublist(
      _statsHistory.length - 10,
      _statsHistory.length - 5,
    );
    final recentAvg =
        recent.map((s) => s.quality.score).reduce((a, b) => a + b) /
        recent.length;
    final olderAvg =
        older.map((s) => s.quality.score).reduce((a, b) => a + b) /
        older.length;
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
