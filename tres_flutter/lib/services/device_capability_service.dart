import 'package:flutter/foundation.dart';
import 'dart:io';

enum DeviceCapability { highEnd, midRange, lowEnd }
enum PreferredCodec { vp9, h264, h265 }

class DeviceCapabilityService {
  static DeviceCapability _capability = DeviceCapability.highEnd;
  static PreferredCodec _preferredCodec = PreferredCodec.h264;
  
  static DeviceCapability get capability => _capability;
  static PreferredCodec get preferredCodec => _preferredCodec;
  
  /// Detect device capability and optimal codec
  static void detectCapability() {
    if (kIsWeb) {
      // Web: Check browser capabilities
      _detectWebCapability();
      return;
    }
    
    try {
      final isIOS = Platform.isIOS;
      final isAndroid = Platform.isAndroid;
      
      if (isIOS) {
        // iOS: High-end, prefers H.264/H.265
        _capability = DeviceCapability.highEnd;
        _preferredCodec = PreferredCodec.h264;
      } else if (isAndroid) {
        // Android: Detect based on performance hints
        _detectAndroidCapability();
      } else {
        _capability = DeviceCapability.midRange;
        _preferredCodec = PreferredCodec.vp9;
      }
      
      debugPrint('📱 Device: ${_capability.name}, Codec: ${_preferredCodec.name}');
    } catch (e) {
      _capability = DeviceCapability.midRange;
      _preferredCodec = PreferredCodec.vp9;
    }
  }
  
  /// Detect web browser capability
  static void _detectWebCapability() {
    // Assume mid-range for web, prefer VP9 (better web support)
    _capability = DeviceCapability.midRange;
    _preferredCodec = PreferredCodec.vp9;
  }
  
  /// Detect Android device capability
  static void _detectAndroidCapability() {
    // Heuristic using number of processors to better detect low-end devices.
    // In the future we can add `device_info_plus` checks (RAM, model) for more accuracy.
    try {
      final processors = Platform.numberOfProcessors;
      if (processors <= 2) {
        _capability = DeviceCapability.lowEnd;
        _preferredCodec = PreferredCodec.vp9;
      } else if (processors <= 4) {
        _capability = DeviceCapability.midRange;
        _preferredCodec = PreferredCodec.vp9;
      } else {
        _capability = DeviceCapability.highEnd;
        _preferredCodec = PreferredCodec.h264;
      }
    } catch (e) {
      // Fallback
      _capability = DeviceCapability.midRange;
      _preferredCodec = PreferredCodec.vp9;
    }
  }
  
  /// Get max video bitrate for device (increased as recommended)
  static int getMaxVideoBitrate() {
    switch (_capability) {
      case DeviceCapability.highEnd:
        return 4000 * 1000; // 4 Mbps - increased from 2.5
      case DeviceCapability.midRange:
        return 2500 * 1000; // 2.5 Mbps - increased from 1.5
      case DeviceCapability.lowEnd:
        return 1200 * 1000; // 1.2 Mbps - increased from 800k
    }
  }
  
  /// Get codec preference string for LiveKit
  static String getCodecPreference() {
    switch (_preferredCodec) {
      case PreferredCodec.vp9:
        return 'VP9';
      case PreferredCodec.h264:
        return 'H264';
      case PreferredCodec.h265:
        return 'H265';
    }
  }
  
  /// Get max framerate for device
  static int getMaxFramerate() {
    switch (_capability) {
      case DeviceCapability.highEnd:
        return 30; // Smooth 30fps
      case DeviceCapability.midRange:
        return 30;
      case DeviceCapability.lowEnd:
        return 24; // Lower for battery/CPU
    }
  }
  
  /// Should use 1080p resolution
  static bool shouldUse1080p() {
    return _capability == DeviceCapability.highEnd;
  }
}