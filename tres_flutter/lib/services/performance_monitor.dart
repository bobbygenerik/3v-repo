import 'dart:async';
import 'package:flutter/foundation.dart';
import 'device_capability_service.dart';
import 'network_quality_service.dart';
import 'livekit_service.dart';
import 'call_features_coordinator.dart';

/// Monitors runtime conditions (network + device) and adapts capture/ML settings.
class PerformanceMonitor {
  final LiveKitService _livekit;
  final CallFeaturesCoordinator _coordinator;
  final NetworkQualityService _network;

  Timer? _timer;
  int _consecutivePoor = 0;

  PerformanceMonitor(this._livekit, this._coordinator, this._network);

  void start() {
    if (_timer != null) return;

    // Check every 5 seconds and adapt if necessary
    _timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final quality = _network.currentQuality;

        // If device is low-end enforce low profile
        if (DeviceCapabilityService.capability == DeviceCapability.lowEnd) {
          await _livekit.applyCaptureProfile(CaptureProfile.low);
          // Ensure ML features are disabled (coordinator already handles this at init but double-check)
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

        if (_consecutivePoor >= 2) {
          // Two checks in a row with poor network -> drop to low
          await _livekit.applyCaptureProfile(CaptureProfile.low);
        } else if (quality == NetworkQuality.fair) {
          await _livekit.applyCaptureProfile(CaptureProfile.medium);
        } else {
          await _livekit.applyCaptureProfile(CaptureProfile.high);
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
