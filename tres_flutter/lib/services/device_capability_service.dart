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
        
        debugPrint('📱 Android: SDK=$sdk, processors=$processors');
        
        // More aggressive detection - most modern phones are high-end
        // SDK 28+ (Android 9+) with 4+ cores = high-end
        if (processors >= 4 && sdk >= 28) {
          _capability = DeviceCapability.highEnd;
          _preferredCodec = PreferredCodec.h264;
        } else if (processors <= 2 || sdk < 26) {
          _capability = DeviceCapability.lowEnd;
          _preferredCodec = PreferredCodec.vp9;
        } else {
          _capability = DeviceCapability.midRange;
          _preferredCodec = PreferredCodec.h264;
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
    // Treat web as high-end for better quality (browsers handle encoding well)
    _capability = DeviceCapability.highEnd;
    _preferredCodec = PreferredCodec.h264; // H.264 for iOS compatibility
    debugPrint('🌐 Web platform detected: Using H.264 codec with high-end bitrate for quality');
  }
  
  /// Detect Android device capability
  static void _detectAndroidCapability() {
    // More aggressive - most Android phones from 2018+ are capable of 1080p
    try {
      final processors = Platform.numberOfProcessors;
      debugPrint('📱 Android processors: $processors');
      
      if (processors <= 2) {
        _capability = DeviceCapability.lowEnd;
        _preferredCodec = PreferredCodec.vp9;
      } else if (processors <= 3) {
        _capability = DeviceCapability.midRange;
        _preferredCodec = PreferredCodec.h264;
      } else {
        // 4+ cores = high-end (covers most phones from 2018+)
        _capability = DeviceCapability.highEnd;
        _preferredCodec = PreferredCodec.h264;
      }
    } catch (e) {
      // Fallback to high-end (better to try high quality and adapt down)
      _capability = DeviceCapability.highEnd;
      _preferredCodec = PreferredCodec.h264;
    }
  }
  
  /// Get max video bitrate for device (FaceTime-level quality)
  /// FaceTime uses ~3-5 Mbps for 1080p, we go higher for headroom
  static int getMaxVideoBitrate() {
    switch (_capability) {
      case DeviceCapability.highEnd:
        return 15000 * 1000; // 15 Mbps for high-end (allows overhead for encoding)
      case DeviceCapability.midRange:
        return 8000 * 1000; // 8 Mbps for mid-range
      case DeviceCapability.lowEnd:
        return 3000 * 1000; // 3 Mbps for low-end
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
        return 30; // 30fps is smooth and efficient (FaceTime uses 30fps)
      case DeviceCapability.midRange:
        return 30;
      case DeviceCapability.lowEnd:
        return 24; // Lower for battery/CPU
    }
  }
  
  /// Should use 1080p resolution
  static bool shouldUse1080p() {
    // Enable 1080p for high-end AND mid-range devices
    // Most phones can handle 1080p capture
    return _capability == DeviceCapability.highEnd || 
           _capability == DeviceCapability.midRange;
  }
}
