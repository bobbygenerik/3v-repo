import 'dart:async';
import 'package:flutter/foundation.dart';
import 'device_capability_service.dart';
import 'network_quality_service.dart';
import 'call_features_coordinator.dart';

/// Monitors runtime conditions (network + device) and adapts capture/ML settings.
class PerformanceMonitor {
  final CallFeaturesCoordinator _coordinator;
  final NetworkQualityService _network;

  Timer? _timer;
  int _consecutivePoor = 0;

  PerformanceMonitor(this._coordinator, this._network);

  void start() {
    if (_timer != null) return;

    // Check every 5 seconds and adapt non-visual features only.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final quality = _network.currentQuality;

        // If device is low-end, disable ML features but keep visual quality locked.
        if (DeviceCapabilityService.capability == DeviceCapability.lowEnd) {
          if (_coordinator.isBackgroundBlurEnabled) {
            await _coordinator.toggleBackgroundBlur();
          }
          if (_coordinator.isBeautyFilterEnabled) {
            _coordinator.toggleBeautyFilter();
          }
          return;
        }

        // Adapt based on network quality
        if (quality == NetworkQuality.poor || quality == NetworkQuality.offline) {
          _consecutivePoor++;
        } else {
          _consecutivePoor = 0;
        }

        if (_consecutivePoor >= 2 || quality == NetworkQuality.fair) {
          // Network is degraded: disable ML features to preserve frame stability.
          if (_coordinator.isBackgroundBlurEnabled) {
            await _coordinator.toggleBackgroundBlur();
          }
          if (_coordinator.isBeautyFilterEnabled) {
            _coordinator.toggleBeautyFilter();
          }
        }
      } catch (e) {
        debugPrint('PerformanceMonitor error: $e');
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
