import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:livekit_client/livekit_client.dart';

enum NetworkQuality { unknown, poor, fair, good, excellent }

enum ConnectionType { unknown, wifi, cellular, ethernet }

class NetworkStats {
  final double latency; // RTT in milliseconds
  final double jitter; // Jitter in milliseconds
  final double packetLoss; // Packet loss percentage
  final double bandwidth; // Available bandwidth in Mbps
  final NetworkQuality quality;
  final ConnectionType connectionType;
  final DateTime timestamp;

  const NetworkStats({
    required this.latency,
    required this.jitter,
    required this.packetLoss,
    required this.bandwidth,
    required this.quality,
    required this.connectionType,
    required this.timestamp,
  });

  static NetworkStats empty() => NetworkStats(
    latency: 0,
    jitter: 0,
    packetLoss: 0,
    bandwidth: 0,
    quality: NetworkQuality.unknown,
    connectionType: ConnectionType.unknown,
    timestamp: DateTime.now(),
  );
}

class EnhancedNetworkQualityService extends ChangeNotifier {
  Timer? _monitoringTimer;
  StreamSubscription<NetworkStats>? _networkStatsSubscription;

  bool _isMonitoring = false;
  NetworkStats _currentStats = NetworkStats.empty();

  // Network monitoring settings
  Duration _monitoringInterval = const Duration(seconds: 3);
  int _maxHistorySize = 50;

  // Network quality thresholds
  static const double _excellentLatencyThreshold = 50.0; // ms
  static const double _goodLatencyThreshold = 100.0; // ms
  static const double _fairLatencyThreshold = 200.0; // ms
  static const double _excellentJitterThreshold = 10.0; // ms
  static const double _goodJitterThreshold = 30.0; // ms
  static const double _fairJitterThreshold = 50.0; // ms
  static const double _excellentPacketLossThreshold = 0.5; // %
  static const double _goodPacketLossThreshold = 2.0; // %
  static const double _fairPacketLossThreshold = 5.0; // %

  // Network quality history
  final List<NetworkStats> _statsHistory = [];

  NetworkStats get currentStats => _currentStats;
  bool get isMonitoring => _isMonitoring;
  List<NetworkStats> get statsHistory => List.unmodifiable(_statsHistory);

  void startMonitoring() {
    if (_isMonitoring) return;

    _isMonitoring = true;

    // Start periodic network quality monitoring
    _monitoringTimer = Timer.periodic(
      _monitoringInterval,
      (_) => _collectNetworkStats(),
    );

    debugPrint('📡 Enhanced network quality monitoring started');
  }

  void stopMonitoring() {
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _networkStatsSubscription?.cancel();
    _monitoringTimer = null;
    _networkStatsSubscription = null;

    debugPrint('📡 Enhanced network quality monitoring stopped');
  }

  Future<void> _collectNetworkStats() async {
    try {
      // In a real implementation, this would collect actual network statistics
      // For now, we'll simulate realistic network stats
      final stats = await _simulateNetworkStats();

      _currentStats = stats;
      _statsHistory.add(stats);

      // Keep only recent history
      if (_statsHistory.length > _maxHistorySize) {
        _statsHistory.removeAt(0);
      }

      // Analyze network quality trends
      _analyzeNetworkTrends();

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error collecting network stats: $e');
    }
  }

  Future<NetworkStats> _simulateNetworkStats() async {
    // Simulate realistic network statistics based on connection type
    final random = math.Random();
    final connectionType = _detectConnectionType();

    double baseLatency, baseJitter, baseBandwidth, basePacketLoss;

    switch (connectionType) {
      case ConnectionType.wifi:
        baseLatency = 20 + random.nextDouble() * 80; // 20-100ms
        baseJitter = 5 + random.nextDouble() * 25; // 5-30ms
        baseBandwidth = 50 + random.nextDouble() * 200; // 50-250 Mbps
        basePacketLoss = random.nextDouble() * 2; // 0-2%
        break;
      case ConnectionType.cellular:
        baseLatency = 50 + random.nextDouble() * 150; // 50-200ms
        baseJitter = 10 + random.nextDouble() * 40; // 10-50ms
        baseBandwidth = 10 + random.nextDouble() * 90; // 10-100 Mbps
        basePacketLoss = random.nextDouble() * 5; // 0-5%
        break;
      case ConnectionType.ethernet:
        baseLatency = 5 + random.nextDouble() * 25; // 5-30ms
        baseJitter = 1 + random.nextDouble() * 9; // 1-10ms
        baseBandwidth = 100 + random.nextDouble() * 900; // 100-1000 Mbps
        basePacketLoss = random.nextDouble() * 0.5; // 0-0.5%
        break;
      default:
        baseLatency = 100 + random.nextDouble() * 200; // 100-300ms
        baseJitter = 20 + random.nextDouble() * 80; // 20-100ms
        baseBandwidth = 5 + random.nextDouble() * 45; // 5-50 Mbps
        basePacketLoss = random.nextDouble() * 10; // 0-10%
    }

    final quality = _calculateNetworkQuality(
      baseLatency,
      baseJitter,
      basePacketLoss,
      baseBandwidth,
    );

    return NetworkStats(
      latency: baseLatency,
      jitter: baseJitter,
      packetLoss: basePacketLoss,
      bandwidth: baseBandwidth,
      quality: quality,
      connectionType: connectionType,
      timestamp: DateTime.now(),
    );
  }

  ConnectionType _detectConnectionType() {
    // In a real implementation, this would detect the actual connection type
    // For simulation, we'll randomly assign types with realistic probabilities
    final random = math.Random();
    final value = random.nextDouble();

    if (value < 0.6) return ConnectionType.wifi;
    if (value < 0.9) return ConnectionType.cellular;
    if (value < 0.95) return ConnectionType.ethernet;
    return ConnectionType.unknown;
  }

  NetworkQuality _calculateNetworkQuality(
    double latency,
    double jitter,
    double packetLoss,
    double bandwidth,
  ) {
    int score = 0;

    // Latency scoring (0-3 points)
    if (latency <= _excellentLatencyThreshold) {
      score += 3;
    } else if (latency <= _goodLatencyThreshold) {
      score += 2;
    } else if (latency <= _fairLatencyThreshold) {
      score += 1;
    }

    // Jitter scoring (0-3 points)
    if (jitter <= _excellentJitterThreshold) {
      score += 3;
    } else if (jitter <= _goodJitterThreshold) {
      score += 2;
    } else if (jitter <= _fairJitterThreshold) {
      score += 1;
    }

    // Packet loss scoring (0-3 points)
    if (packetLoss <= _excellentPacketLossThreshold) {
      score += 3;
    } else if (packetLoss <= _goodPacketLossThreshold) {
      score += 2;
    } else if (packetLoss <= _fairPacketLossThreshold) {
      score += 1;
    }

    // Bandwidth scoring (0-3 points)
    if (bandwidth >= 100) {
      score += 3;
    } else if (bandwidth >= 50) {
      score += 2;
    } else if (bandwidth >= 25) {
      score += 1;
    }

    // Convert score to quality rating
    if (score >= 10) return NetworkQuality.excellent;
    if (score >= 7) return NetworkQuality.good;
    if (score >= 4) return NetworkQuality.fair;
    if (score >= 1) return NetworkQuality.poor;
    return NetworkQuality.unknown;
  }

  void _analyzeNetworkTrends() {
    if (_statsHistory.length < 5) return;

    final recentStats = _statsHistory.length >= 5
        ? _statsHistory.sublist(_statsHistory.length - 5)
        : _statsHistory;
    final avgLatency =
        recentStats.map((s) => s.latency).reduce((a, b) => a + b) /
        recentStats.length;
    final avgPacketLoss =
        recentStats.map((s) => s.packetLoss).reduce((a, b) => a + b) /
        recentStats.length;

    // Detect degrading network conditions
    if (avgLatency > 200 || avgPacketLoss > 3) {
      debugPrint('⚠️ Network quality degradation detected');
      debugPrint('   - Average latency: ${avgLatency.toStringAsFixed(1)}ms');
      debugPrint(
        '   - Average packet loss: ${avgPacketLoss.toStringAsFixed(1)}%',
      );
    }

    // Detect improving network conditions
    if (_statsHistory.length >= 10) {
      final olderStats = _statsHistory.length >= 10
          ? _statsHistory.sublist(
              _statsHistory.length - 10,
              _statsHistory.length - 5,
            )
          : <NetworkStats>[];
      final oldAvgLatency =
          olderStats.map((s) => s.latency).reduce((a, b) => a + b) /
          olderStats.length;

      if (oldAvgLatency - avgLatency > 50) {
        debugPrint('✅ Network quality improvement detected');
        debugPrint(
          '   - Latency improved by: ${(oldAvgLatency - avgLatency).toStringAsFixed(1)}ms',
        );
      }
    }
  }

  int getRecommendedVideoBitrate() {
    switch (_currentStats.quality) {
      case NetworkQuality.excellent:
        return 15000000; // 15 Mbps
      case NetworkQuality.good:
        return 10000000; // 10 Mbps
      case NetworkQuality.fair:
        return 6000000; // 6 Mbps
      case NetworkQuality.poor:
        return 3000000; // 3 Mbps
      default:
        return 5000000; // 5 Mbps fallback
    }
  }

  int getRecommendedAudioBitrate() {
    switch (_currentStats.quality) {
      case NetworkQuality.excellent:
        return 128000; // 128 kbps
      case NetworkQuality.good:
        return 96000; // 96 kbps
      case NetworkQuality.fair:
        return 64000; // 64 kbps
      case NetworkQuality.poor:
        return 32000; // 32 kbps
      default:
        return 64000; // 64 kbps fallback
    }
  }

  int getRecommendedFramerate() {
    switch (_currentStats.quality) {
      case NetworkQuality.excellent:
        return 30;
      case NetworkQuality.good:
        return 30;
      case NetworkQuality.fair:
        return 24;
      case NetworkQuality.poor:
        return 15;
      default:
        return 20; // fallback
    }
  }

  bool shouldUseSimulcast() {
    // Always use simulcast for adaptive quality
    return _currentStats.quality != NetworkQuality.poor;
  }

  Map<String, dynamic> getNetworkMetrics() {
    return {
      'latency': _currentStats.latency,
      'jitter': _currentStats.jitter,
      'packetLoss': _currentStats.packetLoss,
      'bandwidth': _currentStats.bandwidth,
      'quality': _currentStats.quality.name,
      'connectionType': _currentStats.connectionType.name,
      'recommendedVideoBitrate': getRecommendedVideoBitrate(),
      'recommendedAudioBitrate': getRecommendedAudioBitrate(),
      'recommendedFramerate': getRecommendedFramerate(),
    };
  }

  void setMonitoringInterval(Duration interval) {
    if (_monitoringInterval != interval) {
      _monitoringInterval = interval;

      // Restart monitoring with new interval if currently monitoring
      if (_isMonitoring) {
        stopMonitoring();
        startMonitoring();
      }

      debugPrint(
        '📡 Network monitoring interval changed to: ${interval.inSeconds}s',
      );
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
