import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

enum NetworkQuality { excellent, good, fair, poor, offline }

class NetworkQualityService extends ChangeNotifier {
  NetworkQuality _currentQuality = NetworkQuality.good;
  Timer? _qualityTimer;
  bool _isMonitoring = false;
  int _lastLatencyMs = 0;
  
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
  
  /// Get recommended audio bitrate
  int getRecommendedAudioBitrate() {
    switch (_currentQuality) {
      case NetworkQuality.excellent:
      case NetworkQuality.good:
        return 64 * 1000; // 64 kbps
      case NetworkQuality.fair:
        return 48 * 1000; // 48 kbps
      case NetworkQuality.poor:
        return 32 * 1000; // 32 kbps
      case NetworkQuality.offline:
        return 0;
    }
  }
  
  /// Should use video based on network quality
  bool shouldUseVideo() {
    return _currentQuality != NetworkQuality.offline && 
           _currentQuality != NetworkQuality.poor;
  }
  
  /// Get current network type as string
  String getCurrentNetworkType() {
    switch (_currentQuality) {
      case NetworkQuality.excellent:
      case NetworkQuality.good:
        return 'wifi'; // Assume excellent/good quality is WiFi
      case NetworkQuality.fair:
        return '5g'; // Fair quality might be 5G
      case NetworkQuality.poor:
        return '4g'; // Poor quality likely 4G
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
