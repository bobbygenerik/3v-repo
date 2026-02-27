import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
// Conditional import providing web runtime probe implementations
import 'web_runtime_probe_stub.dart'
    if (dart.library.html) 'web_runtime_probe_html.dart';

enum DeviceCapability { highEnd, midRange, lowEnd }

enum PreferredCodec { vp9, h264, h265 }

class DeviceCapabilityService {
  static DeviceCapability _capability = DeviceCapability.highEnd;
  static PreferredCodec _preferredCodec = PreferredCodec.h264;
  // Web runtime capability probes are provided by conditional import functions

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

      debugPrint(
        '📱 Device: ${_capability.name}, Codec: ${_preferredCodec.name}',
      );
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
    debugPrint(
      '📱 (async) Device: ${_capability.name}, Codec: ${_preferredCodec.name}',
    );
  }

  /// Detect web browser capability
  static void _detectWebCapability() {
    // Web platforms, especially iOS Safari, have better H.264 support
    // VP9 is poorly supported on iPhone/Safari browsers
    // Treat web as high-end for better quality (browsers handle encoding well)
    _capability = DeviceCapability.highEnd;
    _preferredCodec = PreferredCodec.h264; // H.264 for iOS compatibility
    debugPrint(
      '🌐 Web platform detected: Using H.264 codec with high-end bitrate for quality',
    );

    // Runtime probe: use conditional web probe helpers (no-op on non-web)
    try {
      final setParams = webHasSetParameters();
      final simulcastOk = webHasSimulcast();
      debugPrint(
        '🌐 Web runtime probe: setParameters=$setParams, simulcastOK=$simulcastOk',
      );
    } catch (e) {
      debugPrint('⚠️ Web runtime probe failed: $e');
    }
  }

  /// Whether the web runtime supports RTCRtpSender.setParameters
  static bool webSupportsSetParameters() => webHasSetParameters();

  /// Whether the web runtime likely supports simulcast (best-effort)
  static bool webSupportsSimulcast() => webHasSimulcast();

  /// Detect Android device capability
  static void _detectAndroidCapability() {
    // More aggressive - most Android phones from 2018+ are capable of 1080p
    try {
      final processors = Platform.numberOfProcessors;
      debugPrint('📱 Android processors: $processors');

      // Special detection for known low-end devices
      if (_isKnownLowEndDevice()) {
        _capability = DeviceCapability.lowEnd;
        _preferredCodec =
            PreferredCodec.h264; // H.264 baseline for compatibility
        debugPrint('🔧 Low-end device detected: Optimized settings applied');
        return;
      }

      if (processors <= 2) {
        _capability = DeviceCapability.lowEnd;
        _preferredCodec =
            PreferredCodec.h264; // Changed from VP9 for better compatibility
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

  /// Check if device is known low-end (Fire tablets, old budget phones)
  static bool _isKnownLowEndDevice() {
    try {
      // Check for Amazon Fire tablets and other known low-end devices
      final brand =
          Platform.environment['ro.product.brand']?.toLowerCase() ?? '';
      final model =
          Platform.environment['ro.product.model']?.toLowerCase() ?? '';

      // Amazon Fire tablets
      if (brand.contains('amazon') || model.contains('fire')) {
        return true;
      }

      // Other known low-end patterns
      final lowEndPatterns = ['mt8', 'sc9', 'unisoc', 'spreadtrum'];
      for (final pattern in lowEndPatterns) {
        if (model.contains(pattern)) {
          return true;
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get max video bitrate for device (EXTREME quality)
  /// Now supporting up to 25 Mbps for 4K calls
  static int getMaxVideoBitrate() {
    switch (_capability) {
      case DeviceCapability.highEnd:
        return 25000 * 1000; // 25 Mbps for high-end 1080p/1440p/4K bursts
      case DeviceCapability.midRange:
        return 8000 * 1000; // 8 Mbps for mid-range 720p/1080p
      case DeviceCapability.lowEnd:
        return 2500 * 1000; // 2.5 Mbps for low-end (stability first)
    }
  }

  /// Get optimized resolution for device
  static Map<String, int> getOptimalResolution() {
    switch (_capability) {
      case DeviceCapability.highEnd:
        return {'width': 1920, 'height': 1080}; // 1080p for flagship
      case DeviceCapability.midRange:
        return {'width': 1280, 'height': 720}; // 720p for mid-range
      case DeviceCapability.lowEnd:
        return {'width': 640, 'height': 480}; // 480p for low-end devices
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
        return 30; // Default 30fps; 60fps is gated by chipset checks elsewhere
      case DeviceCapability.midRange:
        return 30;
      case DeviceCapability.lowEnd:
        return 15; // Much lower for Fire tablets and budget devices
    }
  }

  /// Should use 1080p resolution
  static bool shouldUse1080p() {
    // Enable 1080p for high-end AND mid-range devices
    // Most phones can handle 1080p capture
    return _capability == DeviceCapability.highEnd ||
        _capability == DeviceCapability.midRange;
  }

  /// Get device information map
  static Map<String, dynamic> getDeviceInfo() {
    final Map<String, dynamic> info = {
      'capability': _capability.name,
      'preferredCodec': _preferredCodec.name,
      'isThermalThrottling':
          false, // Simplified - would need platform-specific implementation
      'chipset': _getChipsetInfo(),
      'supportsAV1': _supportsAV1(),
      'supports60fps': _supports60fps(),
    };
    return info;
  }

  /// Get device capability level (1-10 scale)
  static int getDeviceLevel() {
    switch (_capability) {
      case DeviceCapability.highEnd:
        return 9; // High-end devices get level 9
      case DeviceCapability.midRange:
        return 6; // Mid-range devices get level 6
      case DeviceCapability.lowEnd:
        return 3; // Low-end devices get level 3
    }
  }

  /// Get chipset information (simplified)
  static String _getChipsetInfo() {
    if (kIsWeb) return 'web-browser';
    if (Platform.isIOS) return 'apple-silicon';
    if (Platform.isAndroid) {
      // Simplified chipset detection based on processor count
      final processors = Platform.numberOfProcessors;
      if (processors >= 8) return 'snapdragon-8-series';
      if (processors >= 6) return 'snapdragon-7-series';
      return 'snapdragon-6-series';
    }
    return 'unknown';
  }

  /// Check if device supports AV1 codec
  static bool _supportsAV1() {
    final level = getDeviceLevel();
    return level >= 8; // Only high-end devices support AV1
  }

  /// Check if device supports 4K video
  static bool _supports4K() {
    final level = getDeviceLevel();
    final chipset = _getChipsetInfo().toLowerCase();
    return level >= 9 &&
        (chipset.contains('snapdragon 8') ||
            chipset.contains('tensor') ||
            chipset.contains('exynos 2'));
  }

  /// Check if device supports HEVC/H.265
  static bool _supportsHEVC() {
    final level = getDeviceLevel();
    return level >= 8; // Most modern devices support HEVC
  }

  /// Check if device supports 60fps
  static bool _supports60fps() {
    final level = getDeviceLevel();
    final chipset = _getChipsetInfo().toLowerCase();
    return level >= 9 &&
        (chipset.contains('snapdragon 8') ||
            chipset.contains('tensor') ||
            chipset.contains('exynos 2'));
  }
}
