import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:livekit_client/livekit_client.dart';
import 'enhanced_network_quality_service.dart';

enum StreamingProfile { 
  ultraLow,    // 240p, 15fps, 500kbps
  low,         // 360p, 20fps, 800kbps  
  medium,      // 480p, 24fps, 1.2Mbps
  high,        // 720p, 30fps, 2.5Mbps
  ultraHigh,   // 1080p, 30fps, 5Mbps
  adaptive     // Dynamic based on conditions
}

class StreamingStats {
  final int currentBitrate;
  final int targetBitrate;
  final int currentFramerate;
  final int targetFramerate;
  final String currentResolution;
  final String targetResolution;
  final StreamingProfile activeProfile;
  final double adaptationScore; // 0-1, higher = better conditions
  final DateTime timestamp;

  const StreamingStats({
    required this.currentBitrate,
    required this.targetBitrate,
    required this.currentFramerate,
    required this.targetFramerate,
    required this.currentResolution,
    required this.targetResolution,
    required this.activeProfile,
    required this.adaptationScore,
    required this.timestamp,
  });

  static StreamingStats empty() => StreamingStats(
    currentBitrate: 0,
    targetBitrate: 0,
    currentFramerate: 0,
    targetFramerate: 0,
    currentResolution: '0x0',
    targetResolution: '0x0',
    activeProfile: StreamingProfile.medium,
    adaptationScore: 0.5,
    timestamp: DateTime.now(),
  );
}

class AdaptiveStreamingManager extends ChangeNotifier {
  Timer? _adaptationTimer;
  StreamSubscription<NetworkStats>? _networkStatsSubscription;
  
  bool _isActive = false;
  StreamingStats _currentStats = StreamingStats.empty();
  StreamingProfile _currentProfile = StreamingProfile.adaptive;
  
  // Adaptation settings
  Duration _adaptationInterval = const Duration(seconds: 5);
  double _adaptationSensitivity = 0.7; // 0-1, higher = more aggressive
  int _stabilityWindow = 3; // Number of measurements before adapting
  
  // Quality thresholds for adaptation
  static const double _excellentThreshold = 0.8;
  static const double _goodThreshold = 0.6;
  static const double _fairThreshold = 0.4;
  static const double _poorThreshold = 0.2;
  
  // Streaming profiles configuration
  static const Map<StreamingProfile, Map<String, dynamic>> _profileConfigs = {
    StreamingProfile.ultraLow: {
      'resolution': '426x240',
      'dimensions': [426, 240],
      'framerate': 15,
      'bitrate': 500000,
      'description': 'Ultra Low (240p)',
    },
    StreamingProfile.low: {
      'resolution': '640x360',
      'dimensions': [640, 360],
      'framerate': 20,
      'bitrate': 800000,
      'description': 'Low (360p)',
    },
    StreamingProfile.medium: {
      'resolution': '854x480',
      'dimensions': [854, 480],
      'framerate': 24,
      'bitrate': 1200000,
      'description': 'Medium (480p)',
    },
    StreamingProfile.high: {
      'resolution': '1280x720',
      'dimensions': [1280, 720],
      'framerate': 30,
      'bitrate': 2500000,
      'description': 'High (720p)',
    },
    StreamingProfile.ultraHigh: {
      'resolution': '1920x1080',
      'dimensions': [1920, 1080],
      'framerate': 30,
      'bitrate': 5000000,
      'description': 'Ultra High (1080p)',
    },
  };
  
  // Adaptation history for stability
  final List<double> _adaptationScores = [];
  
  StreamingStats get currentStats => _currentStats;
  bool get isActive => _isActive;
  StreamingProfile get currentProfile => _currentProfile;

  void startAdaptiveStreaming(EnhancedNetworkQualityService networkService) {
    if (_isActive) return;
    
    _isActive = true;
    
    // Listen to network quality changes
    networkService.addListener(() {
      _handleNetworkQualityChange(networkService.currentStats);
    });
    
    // Start periodic adaptation evaluation
    _adaptationTimer = Timer.periodic(
      _adaptationInterval,
      (_) => _evaluateAdaptation(networkService.currentStats),
    );
    
    debugPrint('🎬 Adaptive streaming manager started');
  }

  void stopAdaptiveStreaming() {
    _isActive = false;
    _adaptationTimer?.cancel();
    _networkStatsSubscription?.cancel();
    _adaptationTimer = null;
    _networkStatsSubscription = null;
    
    debugPrint('🎬 Adaptive streaming manager stopped');
  }

  void _handleNetworkQualityChange(NetworkStats networkStats) {
    // Calculate adaptation score based on network conditions
    final adaptationScore = _calculateAdaptationScore(networkStats);
    
    // Add to history for stability analysis
    _adaptationScores.add(adaptationScore);
    if (_adaptationScores.length > _stabilityWindow * 2) {
      _adaptationScores.removeAt(0);
    }
    
    // Update current stats
    _updateCurrentStats(networkStats, adaptationScore);
    
    notifyListeners();
  }

  double _calculateAdaptationScore(NetworkStats networkStats) {
    double score = 1.0;
    
    // Latency impact (0-0.3 penalty)
    if (networkStats.latency > 200) {
      score -= 0.3;
    } else if (networkStats.latency > 100) {
      score -= 0.15;
    } else if (networkStats.latency > 50) {
      score -= 0.05;
    }
    
    // Jitter impact (0-0.2 penalty)
    if (networkStats.jitter > 50) {
      score -= 0.2;
    } else if (networkStats.jitter > 30) {
      score -= 0.1;
    } else if (networkStats.jitter > 10) {
      score -= 0.05;
    }
    
    // Packet loss impact (0-0.4 penalty)
    if (networkStats.packetLoss > 5) {
      score -= 0.4;
    } else if (networkStats.packetLoss > 2) {
      score -= 0.2;
    } else if (networkStats.packetLoss > 0.5) {
      score -= 0.1;
    }
    
    // Bandwidth boost (0-0.1 bonus)
    if (networkStats.bandwidth > 100) {
      score += 0.1;
    } else if (networkStats.bandwidth > 50) {
      score += 0.05;
    }
    
    return math.max(0.0, math.min(1.0, score));
  }

  void _updateCurrentStats(NetworkStats networkStats, double adaptationScore) {
    final targetProfile = _determineOptimalProfile(adaptationScore);
    final targetConfig = _profileConfigs[targetProfile];
    
    if (targetConfig != null) {
      _currentStats = StreamingStats(
        currentBitrate: _currentStats.currentBitrate,
        targetBitrate: targetConfig['bitrate'] as int,
        currentFramerate: _currentStats.currentFramerate,
        targetFramerate: targetConfig['framerate'] as int,
        currentResolution: _currentStats.currentResolution,
        targetResolution: targetConfig['resolution'] as String,
        activeProfile: targetProfile,
        adaptationScore: adaptationScore,
        timestamp: DateTime.now(),
      );
    }
  }

  StreamingProfile _determineOptimalProfile(double adaptationScore) {
    if (_currentProfile != StreamingProfile.adaptive) {
      return _currentProfile; // Manual profile override
    }
    
    // Determine profile based on adaptation score
    if (adaptationScore >= _excellentThreshold) {
      return StreamingProfile.ultraHigh;
    } else if (adaptationScore >= _goodThreshold) {
      return StreamingProfile.high;
    } else if (adaptationScore >= _fairThreshold) {
      return StreamingProfile.medium;
    } else if (adaptationScore >= _poorThreshold) {
      return StreamingProfile.low;
    } else {
      return StreamingProfile.ultraLow;
    }
  }

  Future<void> _evaluateAdaptation(NetworkStats networkStats) async {
    if (!_isActive || _adaptationScores.length < _stabilityWindow) return;
    
    try {
      // Check if conditions are stable enough for adaptation
      final recentScores = _adaptationScores.length >= _stabilityWindow 
        ? _adaptationScores.sublist(_adaptationScores.length - _stabilityWindow)
        : _adaptationScores;
      final avgScore = recentScores.reduce((a, b) => a + b) / recentScores.length;
      final scoreVariance = _calculateVariance(recentScores);
      
      // Only adapt if conditions are relatively stable
      if (scoreVariance < 0.1) {
        final optimalProfile = _determineOptimalProfile(avgScore);
        
        if (optimalProfile != _currentStats.activeProfile) {
          await _adaptToProfile(optimalProfile);
        }
      }
    } catch (e) {
      debugPrint('❌ Error during adaptation evaluation: $e');
    }
  }

  double _calculateVariance(List<double> values) {
    if (values.isEmpty) return 0.0;
    
    final mean = values.reduce((a, b) => a + b) / values.length;
    final squaredDiffs = values.map((value) => math.pow(value - mean, 2));
    return squaredDiffs.reduce((a, b) => a + b) / values.length;
  }

  Future<void> _adaptToProfile(StreamingProfile profile) async {
    try {
      final config = _profileConfigs[profile];
      if (config == null) return;
      
      debugPrint('🔄 Adapting to ${config['description']}');
      debugPrint('   - Resolution: ${config['resolution']}');
      debugPrint('   - Framerate: ${config['framerate']}fps');
      debugPrint('   - Bitrate: ${((config['bitrate'] as int) / 1000000).toStringAsFixed(1)}Mbps');
      
      // Update current stats to reflect the adaptation
      _currentStats = StreamingStats(
        currentBitrate: config['bitrate'] as int,
        targetBitrate: config['bitrate'] as int,
        currentFramerate: config['framerate'] as int,
        targetFramerate: config['framerate'] as int,
        currentResolution: config['resolution'] as String,
        targetResolution: config['resolution'] as String,
        activeProfile: profile,
        adaptationScore: _currentStats.adaptationScore,
        timestamp: DateTime.now(),
      );
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error adapting to profile: $e');
    }
  }

  void setProfile(StreamingProfile profile) {
    if (_currentProfile != profile) {
      _currentProfile = profile;
      debugPrint('🎬 Streaming profile changed to: ${profile.name}');
      
      if (profile != StreamingProfile.adaptive) {
        // Manual profile - apply immediately
        _adaptToProfile(profile);
      }
      
      notifyListeners();
    }
  }

  void setAdaptationSensitivity(double sensitivity) {
    _adaptationSensitivity = math.max(0.0, math.min(1.0, sensitivity));
    debugPrint('🎛️ Adaptation sensitivity set to: ${(_adaptationSensitivity * 100).toStringAsFixed(0)}%');
  }

  VideoParameters getVideoParameters() {
    final config = _profileConfigs[_currentStats.activeProfile];
    if (config == null) {
      return VideoParameters(
        dimensions: VideoDimensions(854, 480),
        encoding: VideoEncoding(maxBitrate: 1200000, maxFramerate: 24),
      );
    }
    
    final dimensions = config['dimensions'] as List<int>;
    return VideoParameters(
      dimensions: VideoDimensions(dimensions[0], dimensions[1]),
      encoding: VideoEncoding(
        maxBitrate: config['bitrate'] as int,
        maxFramerate: config['framerate'] as int,
      ),
    );
  }

  List<VideoParameters> getSimulcastLayers() {
    final baseConfig = _profileConfigs[_currentStats.activeProfile];
    if (baseConfig == null) return [];
    
    final layers = <VideoParameters>[];
    
    // High quality layer (current profile)
    final baseDimensions = baseConfig['dimensions'] as List<int>;
    layers.add(VideoParameters(
      dimensions: VideoDimensions(baseDimensions[0], baseDimensions[1]),
      encoding: VideoEncoding(
        maxBitrate: baseConfig['bitrate'] as int,
        maxFramerate: baseConfig['framerate'] as int,
      ),
    ));
    
    // Medium quality layer (50% resolution, 60% bitrate)
    final mediumWidth = (baseDimensions[0] * 0.7).round();
    final mediumHeight = (baseDimensions[1] * 0.7).round();
    layers.add(VideoParameters(
      dimensions: VideoDimensions(mediumWidth, mediumHeight),
      encoding: VideoEncoding(
        maxBitrate: ((baseConfig['bitrate'] as int) * 0.6).round(),
        maxFramerate: baseConfig['framerate'] as int,
      ),
    ));
    
    // Low quality layer (360p, 30% bitrate)
    layers.add(VideoParameters(
      dimensions: VideoDimensions(640, 360),
      encoding: VideoEncoding(
        maxBitrate: ((baseConfig['bitrate'] as int) * 0.3).round(),
        maxFramerate: math.min(20, baseConfig['framerate'] as int),
      ),
    ));
    
    return layers;
  }

  Map<String, dynamic> getStreamingMetrics() {
    return {
      'currentProfile': _currentStats.activeProfile.name,
      'currentBitrate': _currentStats.currentBitrate,
      'targetBitrate': _currentStats.targetBitrate,
      'currentFramerate': _currentStats.currentFramerate,
      'targetFramerate': _currentStats.targetFramerate,
      'currentResolution': _currentStats.currentResolution,
      'targetResolution': _currentStats.targetResolution,
      'adaptationScore': _currentStats.adaptationScore,
      'adaptationSensitivity': _adaptationSensitivity,
      'isAdaptive': _currentProfile == StreamingProfile.adaptive,
    };
  }

  @override
  void dispose() {
    stopAdaptiveStreaming();
    super.dispose();
  }
}