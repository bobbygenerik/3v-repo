import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'call_stats_model.dart';

enum NetworkQuality { excellent, good, fair, poor, offline }

class NetworkQualityService extends ChangeNotifier {
  NetworkQuality _currentQuality = NetworkQuality.good;
  Timer? _qualityTimer;
  bool _isMonitoring = false;
  int _lastLatencyMs = 0;
  DateTime? _lastStatsAt;
  
  NetworkQuality get currentQuality => _currentQuality;
  bool get isMonitoring => _isMonitoring;
  
  /// Start monitoring network quality
  void startMonitoring() {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    _qualityTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkNetworkQuality();
    });
    
    // Initial check
    _checkNetworkQuality();
  }
  
  /// Stop monitoring
  void stopMonitoring() {
    _isMonitoring = false;
    _qualityTimer?.cancel();
    _qualityTimer = null;
  }
  
  /// Check network quality by measuring latency
  Future<void> _checkNetworkQuality() async {
    final now = DateTime.now();
    if (_lastStatsAt != null &&
        now.difference(_lastStatsAt!) < const Duration(seconds: 10)) {
      return;
    }
    try {
      final endpoints = <Uri>[
        Uri.parse('https://www.gstatic.com/generate_204'),
        Uri.parse('https://www.google.com/generate_204'),
        Uri.parse('https://cloudflare.com/cdn-cgi/trace'),
      ];
      int? latency;
      int? statusCode;

      for (final endpoint in endpoints) {
        final stopwatch = Stopwatch()..start();
        try {
          final response = await http.head(endpoint).timeout(const Duration(seconds: 5));
          stopwatch.stop();
          latency = stopwatch.elapsedMilliseconds;
          statusCode = response.statusCode;
          break;
        } catch (_) {
          stopwatch.stop();
          continue;
        }
      }

      if (latency == null) {
        throw Exception('No network probe succeeded');
      }

      _lastLatencyMs = latency;
      
      NetworkQuality newQuality;
      if (statusCode == 204 || statusCode == 200) {
        if (latency < 50) {
          newQuality = NetworkQuality.excellent;
        } else if (latency < 150) {
          newQuality = NetworkQuality.good;
        } else if (latency < 300) {
          newQuality = NetworkQuality.fair;
        } else {
          newQuality = NetworkQuality.poor;
        }
      } else {
        newQuality = NetworkQuality.poor;
      }
      
      if (newQuality != _currentQuality) {
        _currentQuality = newQuality;
        notifyListeners();
        debugPrint('📶 Network quality: ${newQuality.name} (${latency}ms)');
      }
    } catch (e) {
      if (_currentQuality != NetworkQuality.offline) {
        _currentQuality = NetworkQuality.offline;
        notifyListeners();
        debugPrint('📶 Network offline');
      }
    }
  }

  /// Update quality from LiveKit stats (preferred over latency probes).
  void updateFromCallStats(CallStats stats) {
    final packetLoss = stats.videoPacketLoss > stats.audioPacketLoss
        ? stats.videoPacketLoss
        : stats.audioPacketLoss;
    final rttMs = stats.roundTripTime * 1000.0;
    final jitterMs = stats.jitter * 1000.0;
    final outgoing = stats.availableOutgoingBitrate;

    if (packetLoss <= 0 &&
        rttMs <= 0 &&
        jitterMs <= 0 &&
        outgoing <= 0) {
      return;
    }

    _lastStatsAt = DateTime.now();
    if (rttMs > 0) {
      _lastLatencyMs = rttMs.round();
    }

    NetworkQuality newQuality;
    if (outgoing >= 15_000_000 &&
        packetLoss < 1.0 &&
        rttMs < 80 &&
        jitterMs < 10) {
      newQuality = NetworkQuality.excellent;
    } else if (outgoing >= 8_000_000 &&
        packetLoss < 2.5 &&
        rttMs < 150 &&
        jitterMs < 20) {
      newQuality = NetworkQuality.good;
    } else if (outgoing >= 3_000_000 &&
        packetLoss < 5.0 &&
        rttMs < 250 &&
        jitterMs < 40) {
      newQuality = NetworkQuality.fair;
    } else {
      newQuality = NetworkQuality.poor;
    }

    if (newQuality != _currentQuality) {
      _currentQuality = newQuality;
      notifyListeners();
      debugPrint(
        '📶 Network quality (stats): ${newQuality.name} '
        '(loss ${packetLoss.toStringAsFixed(1)}%, rtt ${rttMs.toStringAsFixed(0)}ms)',
      );
    }
  }
  
  /// Get recommended video bitrate based on network quality (EXTREME QUALITY)
  int getRecommendedVideoBitrate() {
    switch (_currentQuality) {
      case NetworkQuality.excellent:
        return 25000 * 1000; // 25 Mbps (4K/1440p headroom)
      case NetworkQuality.good:
        return 20000 * 1000; // 20 Mbps (1440p 60fps)
      case NetworkQuality.fair:
        return 12000 * 1000; // 12 Mbps (enhanced 1080p)
      case NetworkQuality.poor:
        return 6000 * 1000;  // 6 Mbps (720p floor)
      case NetworkQuality.offline:
        return 0;
    }
  }

  /// Return last measured latency in milliseconds (may be 0 if not measured)
  int getLastMeasuredLatencyMs() => _lastLatencyMs;
  
  /// Get recommended audio bitrate.
  /// Opus at 64 kbps gives FaceTime-quality voice. Even at 48 kbps (poor
  /// network) the improvement over 32 kbps is clearly audible.
  int getRecommendedAudioBitrate() {
    switch (_currentQuality) {
      case NetworkQuality.excellent:
        return 64 * 1000; // 64 kbps — full HD voice
      case NetworkQuality.good:
        return 64 * 1000; // 64 kbps
      case NetworkQuality.fair:
        return 48 * 1000; // 48 kbps
      case NetworkQuality.poor:
        return 40 * 1000; // 40 kbps — still clear speech
      case NetworkQuality.offline:
        return 0;
    }
  }
  
  /// Should use video based on network quality
  bool shouldUseVideo() {
    return _currentQuality != NetworkQuality.offline && 
           _currentQuality != NetworkQuality.poor;
  }
  
  /// Returns whether the current connection has enough bandwidth headroom for
  /// ultra-high-quality video (equivalent to being on WiFi or strong 5G).
  /// This replaces the old getCurrentNetworkType() quality→type guess, which
  /// was wrong: poor WiFi was classified as '4g', blocking UltraHQ on WiFi.
  bool isHighBandwidthConnection() {
    return _currentQuality == NetworkQuality.excellent ||
        _currentQuality == NetworkQuality.good;
  }

  /// Get current network type as string.
  /// NOTE: This maps quality level to a bandwidth category, not a physical
  /// interface type (WiFi vs cellular). Use isHighBandwidthConnection() for
  /// bandwidth gates and add connectivity_plus if the physical type is needed.
  String getCurrentNetworkType() {
    switch (_currentQuality) {
      case NetworkQuality.excellent:
        return 'wifi';
      case NetworkQuality.good:
        return 'wifi';
      case NetworkQuality.fair:
        return '5g';
      case NetworkQuality.poor:
        return '4g';
      case NetworkQuality.offline:
        return 'none';
    }
  }
  
  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
