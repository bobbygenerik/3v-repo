import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

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

  /// Async detection using device_info_plus for more accurate classification.
  static Future<void> detectCapabilityAsync() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        final sdk = info.version.sdkInt ?? 0;
        final processors = Platform.numberOfProcessors;
        // Heuristic: newer Android SDK + more CPUs -> higher capability
        if (processors >= 8 && sdk >= 29) {
          _capability = DeviceCapability.highEnd;
          _preferredCodec = PreferredCodec.h264;
        } else if (processors <= 2) {
          _capability = DeviceCapability.lowEnd;
          _preferredCodec = PreferredCodec.vp9;
        } else {
          _capability = DeviceCapability.midRange;
          _preferredCodec = PreferredCodec.vp9;
        }
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        // Assume modern iOS devices are high-end; older ones mid-range
        final systemVersion = double.tryParse(info.systemVersion ?? '0') ?? 0;
        if (systemVersion >= 14) {
          _capability = DeviceCapability.highEnd;
          _preferredCodec = PreferredCodec.h264;
        } else {
          _capability = DeviceCapability.midRange;
          _preferredCodec = PreferredCodec.h264;
        }
      }
    } catch (e) {
      // fallback to synchronous detection
      detectCapability();
    }
    debugPrint('📱 (async) Device: ${_capability.name}, Codec: ${_preferredCodec.name}');
  }
  
  /// Detect web browser capability
  static void _detectWebCapability() {
    // Web platforms, especially iOS Safari, have better H.264 support
    // VP9 is poorly supported on iPhone/Safari browsers
    _capability = DeviceCapability.midRange;
    _preferredCodec = PreferredCodec.h264; // Changed from VP9 for iOS compatibility
    debugPrint('🌐 Web platform detected: Using H.264 codec for iOS/Safari compatibility');
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
        return 12000 * 1000; // 12 Mbps for high-end devices
      case DeviceCapability.midRange:
        return 5000 * 1000; // 5 Mbps for mid-range
      case DeviceCapability.lowEnd:
        return 2000 * 1000; // 2 Mbps for low-end
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
        return 60; // Allow 60fps on high-end devices for very smooth video
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