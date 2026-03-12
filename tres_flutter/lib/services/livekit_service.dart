import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'network_quality_service.dart';
import 'device_capability_service.dart';
import 'device_mode_service.dart';
import 'call_stats_service.dart';
import '../config/environment.dart';
import 'feature_flags.dart';
import 'ice_server_config.dart';
// MediaPipe removed: no mediapipe_settings import
import 'web_pip_helper.dart';
import 'web_pip_bridge_stub.dart'
    if (dart.library.html) 'web_pip_bridge.dart';
import 'dart:io' show Platform;
// `CallStats` and `CallConnectionQuality` are exported via `call_stats_service.dart`

/// LiveKit service managing room connections and participant tracks
/// Implements FaceTime-quality tuning for maximum video quality
enum CallType { androidAndroid, androidIOSPWA, iosPWAIOSPWA, mixedUnknown }
enum CaptureProfile { low, medium, high }
enum QualityTier { low, medium, high, ultra }

/// Custom video presets following FaceTime-quality tuning brief
class FaceTimeVideoPresets {
  // Cross-Platform 1080p HQ
  static final h1080 = VideoParameters(
    dimensions: VideoDimensions(1920, 1080),
    encoding: VideoEncoding(maxBitrate: 12_000_000, maxFramerate: 30),
  );

  // Cross-Platform 720p Fallback
  static final h720 = VideoParameters(
    dimensions: VideoDimensions(1280, 720),
    // Target 720p at ~3 Mbps for improved clarity
    encoding: VideoEncoding(maxBitrate: 3_000_000, maxFramerate: 30),
  );

  // 720p Low-FPS Stability (never drop below 720p)
  static final h720LowFps = VideoParameters(
    dimensions: VideoDimensions(1280, 720),
    encoding: VideoEncoding(maxBitrate: 2_000_000, maxFramerate: 12),
  );

  // 720p Emergency (minimum FPS, last resort)
  static final h720Emergency = VideoParameters(
    dimensions: VideoDimensions(1280, 720),
    encoding: VideoEncoding(maxBitrate: 1_800_000, maxFramerate: 10),
  );

  // Android Ultra-HQ 1080p+
  static final androidUltraHQ = VideoParameters(
    dimensions: VideoDimensions(1920, 1080),
    encoding: VideoEncoding(maxBitrate: 12_000_000, maxFramerate: 30),
  );

  // Android Ultra-HQ 60 FPS (High-End Devices Only)
  static final androidUltraHQ60 = VideoParameters(
    dimensions: VideoDimensions(1920, 1080),
    encoding: VideoEncoding(maxBitrate: 15_000_000, maxFramerate: 60),
  );

  // EXTREME QUALITY - 4K Support for flagship devices
  static final androidExtreme4K = VideoParameters(
    dimensions: VideoDimensions(3840, 2160),
    encoding: VideoEncoding(maxBitrate: 25_000_000, maxFramerate: 30),
  );

  // EXTREME QUALITY - 1440p 60fps
  static final androidExtreme1440p60 = VideoParameters(
    dimensions: VideoDimensions(2560, 1440),
    encoding: VideoEncoding(maxBitrate: 20_000_000, maxFramerate: 60),
  );

  // Opportunistic 1440p layer for simulcast ladder (target ~9-10 Mbps)
  static final h1440 = VideoParameters(
    dimensions: VideoDimensions(2560, 1440),
    encoding: VideoEncoding(maxBitrate: 12_000_000, maxFramerate: 30),
  );

  // Android-Only Ultra-HQ 720p
  static final androidUltraHQ720 = VideoParameters(
    dimensions: VideoDimensions(1280, 720),
    encoding: VideoEncoding(maxBitrate: 5_000_000, maxFramerate: 30),
  );

}

class LiveKitService extends ChangeNotifier {
  Room? _room;
  LocalVideoTrack? _localVideoTrack;
  LocalAudioTrack? _localAudioTrack;
  CallType _currentCallType = CallType.mixedUnknown;
  bool _isUltraHQMode = false;
  bool _isSimulcastEnabled = false;
  String? _mediaPipeError;
  bool _isRecoveringAudio = false;
  String _currentVideoCodec = 'h264';
  bool _adaptiveBitrateEnabled = true;
  int? _currentAdaptiveBitrate;
  DateTime? _lastAdaptiveChange;
  DateTime? _lastSimulcastChange;
  QualityTier _currentQualityTier = QualityTier.high;
  DateTime? _lastQualityTierChange;
  DateTime? _qualityUpgradeGateStart;
  DateTime? _qualityDownshiftStart;
  DateTime? _qualityUpshiftStart;
  final List<double> _recentSendBitrates = [];
  final List<double> _recentAvailableOutgoingBitrates = [];
  VideoParameters? _currentCapturePreset;
  CameraPosition _currentCameraPosition = CameraPosition.front;
  bool _isReconnecting = false;
  bool _manualDisconnect = false;
  bool _abortConnect = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  String? _lastUrl;
  String? _lastToken;
  String? _lastRoomName;
  
  Room? get room => _room;
  LocalVideoTrack? get localVideoTrack => _localVideoTrack;
  LocalAudioTrack? get localAudioTrack => _localAudioTrack;
  CallType get currentCallType => _currentCallType;
  bool get isUltraHQMode => _isUltraHQMode;
  bool get isSimulcastEnabled => _isSimulcastEnabled;
  QualityTier get currentQualityTier => _currentQualityTier;
  String? consumeMediaPipeError() {
    final error = _mediaPipeError;
    _mediaPipeError = null;
    return error;
  }
  String get currentVideoCodec => _currentVideoCodec;
  bool get isReconnecting => _isReconnecting;
  
  bool get isConnected => _room?.connectionState == ConnectionState.connected;
  bool get isMicrophoneEnabled => _localAudioTrack?.muted == false;
  bool get isCameraEnabled => _localVideoTrack?.muted == false;
  
  List<Participant> get remoteParticipants => 
      _room?.remoteParticipants.values.toList() ?? [];
  
  LocalParticipant? get localParticipant => _room?.localParticipant;
  
  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  
  final NetworkQualityService _networkService = NetworkQualityService();
  // Runtime mode
  final bool _isSafariPwa = DeviceModeService.isSafariPwa();
  CallStatsService? _internalStatsService;
  final WebPipService _pipService = WebPipService();
  // MediaPipe removed: no processor or settings retained
  
  AudioCaptureOptions? _customAudioCaptureOptions;

  /// Get the PiP service for web platforms
  WebPipService get pipService => _pipService;
  
  // Detect device capability on service creation
  LiveKitService() {
    DeviceCapabilityService.detectCapability();
    DeviceCapabilityService.detectCapabilityAsync();
    // Apply conservative defaults with centralized feature flags.
    // Safari PWA gets additional conservative enforcement.
    _adaptiveBitrateEnabled = FeatureFlags.enableAdaptiveBitrate && !_isSafariPwa;
    // Use simulcast ladder flag (3-layer) but gate by runtime capability probe on web
    var webSimulcastOk = true;
    if (kIsWeb) {
      webSimulcastOk = DeviceCapabilityService.webSupportsSimulcast();
    }
    _isSimulcastEnabled = FeatureFlags.enableSimulcastLadder && !_isSafariPwa && webSimulcastOk;
  }

  /// Determine call type at runtime (Required by brief)
  CallType _classifyCallType() {
    if (remoteParticipants.isEmpty) return CallType.mixedUnknown;

    final participant = remoteParticipants.first;
    final localIsWeb = kIsWeb;
    final remotePlatform = _inferParticipantPlatform(participant);
    final remoteIsAndroid = remotePlatform.contains('android');
    final remoteIsWeb = remotePlatform.contains('web') || remotePlatform.contains('ios');

    if (!localIsWeb && DeviceModeService.isAndroidNative() && remoteIsAndroid) {
      return CallType.androidAndroid;
    }
    if (!localIsWeb && DeviceModeService.isAndroidNative() && remoteIsWeb) {
      return CallType.androidIOSPWA;
    }
    if (localIsWeb && remoteIsWeb) {
      return CallType.iosPWAIOSPWA;
    }

    return CallType.mixedUnknown;
  }

  String _inferParticipantPlatform(Participant participant) {
    final identity = participant.identity.toLowerCase();
    final metadata = participant.metadata;

    if (metadata != null && metadata.isNotEmpty) {
      try {
        final decoded = jsonDecode(metadata);
        if (decoded is Map && decoded['platform'] is String) {
          return (decoded['platform'] as String).toLowerCase();
        }
      } catch (_) {}
      final metaLower = metadata.toLowerCase();
      if (metaLower.contains('android')) return 'android';
      if (metaLower.contains('ios')) return 'ios';
      if (metaLower.contains('web')) return 'web';
    }

    if (identity.contains('android')) return 'android';
    if (identity.contains('ios')) return 'ios';
    if (identity.contains('web')) return 'web';
    return 'unknown';
  }

  /// Check if Android Ultra-HQ conditions are met (Required by brief)
  bool _shouldEnableUltraHQ() {
    // Enable ONLY if:
    // * Both peers are Android native
    // * Same app build
    // * Thermal state = normal
    // * Network = Wi-Fi or strong 5G
    
    if (_currentCallType != CallType.androidAndroid) return false;

    // Require high-bandwidth connection (excellent or good quality).
    // Previously this guessed network *type* from quality level, which caused
    // poor WiFi to be classified as '4g' and block UltraHQ even on WiFi.
    if (!_networkService.isHighBandwidthConnection()) return false;
    
    // Check thermal state (simplified check)
    final deviceInfo = DeviceCapabilityService.getDeviceInfo();
    if (deviceInfo['isThermalThrottling'] == true) return false;
    
    // Check if high-end device
    final deviceLevel = DeviceCapabilityService.getDeviceLevel();
    if (deviceLevel < 8) return false; // Only flagship devices

    // Honor global feature flag for ultra quality
    return FeatureFlags.enableUltraQuality;
  }

  /// Get platform-aware codec strategy (Required by brief)
  String _getPreferredCodec() {
    switch (_currentCallType) {
      case CallType.androidAndroid:
        // Android ↔ Android: AV1 (if supported), H.264 High Profile, VP9 fallback
        if (_supportsAV1()) return 'av1';
        return 'h264';
        
      case CallType.androidIOSPWA:
      case CallType.iosPWAIOSPWA:
      case CallType.mixedUnknown:
        // Default Cross-Platform: H.264 High Profile, VP9, VP8
        return 'h264';
    }
  }

  String _getPublishVideoCodec() {
    if (_isSafariPwa) return 'h264';
    return _currentVideoCodec;
  }

  VideoPublishOptions _buildVideoPublishOptions(VideoEncoding encoding) {
    final codec = _getPublishVideoCodec();
    BackupVideoCodec? backup;
    if (codec == 'av1') {
      backup = BackupVideoCodec(
        codec: 'h264',
        simulcast: _isSimulcastEnabled,
      );
    }
    return VideoPublishOptions(
      videoEncoding: encoding,
      simulcast: _isSimulcastEnabled,
      videoCodec: codec,
      backupVideoCodec: backup ?? VideoPublishOptions.defualtBackupVideoCodec,
      // maintainResolution: keep image sharp and only reduce framerate under
      // congestion — mirrors Apple FaceTime's quality strategy.
      degradationPreference: DegradationPreference.maintainResolution,
    );
  }

  /// Get conservative encoding for Safari PWA
  VideoEncoding _getSafariPwaEncoding() {
    // Hard cap to 720p @ 30fps with conservative bitrate
    return const VideoEncoding(maxBitrate: 1800000, maxFramerate: 30);
  }

  /// Check AV1 support
  bool _supportsAV1() {
    // Use device capability service's built-in AV1 detection
    final deviceInfo = DeviceCapabilityService.getDeviceInfo();
    return deviceInfo['supportsAV1'] == true;
  }

  /// Check if device supports 60fps
  bool _supports60fps() {
    final deviceLevel = DeviceCapabilityService.getDeviceLevel();
    final chipset = DeviceCapabilityService.getDeviceInfo()['chipset']?.toLowerCase() ?? '';
    
    return deviceLevel >= 9 && (
      chipset.contains('snapdragon 8 gen') ||
      chipset.contains('tensor g') ||
      chipset.contains('exynos 2')
    );
  }

  /// Check if device supports 4K recording
  bool _supports4K() {
    final deviceLevel = DeviceCapabilityService.getDeviceLevel();
    final chipset = DeviceCapabilityService.getDeviceInfo()['chipset']?.toLowerCase() ?? '';
    
    return deviceLevel >= 9 && (
      chipset.contains('snapdragon 8 gen 2') ||
      chipset.contains('snapdragon 8 gen 3') ||
      chipset.contains('tensor g3') ||
      chipset.contains('exynos 2400')
    );
  }

  /// Check if device supports 1440p 60fps
  bool _supports1440p60() {
    final deviceLevel = DeviceCapabilityService.getDeviceLevel();
    final chipset = DeviceCapabilityService.getDeviceInfo()['chipset']?.toLowerCase() ?? '';
    
    return deviceLevel >= 9 && (
      chipset.contains('snapdragon 8 gen') ||
      chipset.contains('tensor g') ||
      chipset.contains('exynos 2')
    );
  }

  /// Collect call stats from local tracks using LiveKit SDK where available.
  Future<CallStats> collectCallStats() async {
    try {
      if (_room == null) return const CallStats();

      _internalStatsService ??= CallStatsService();
      try {
        await _internalStatsService!.initialize(_room!);
      } catch (_) {}
      if (!_internalStatsService!.isCollecting) {
        _internalStatsService!.startCollecting();
      }

      return _internalStatsService!.currentStats;
    } catch (e) {
      debugPrint('collectCallStats fatal: $e');
      return const CallStats();
    }
  }
  
  /// Get FaceTime-quality video encoding
  VideoEncoding _getOptimalVideoEncoding([VideoParameters? preset]) {
    _currentCallType = _classifyCallType();
    _isUltraHQMode = _shouldEnableUltraHQ();
    _currentVideoCodec = _getPreferredCodec();
    
    final deviceMaxBitrate = DeviceCapabilityService.getMaxVideoBitrate();
    final deviceMaxFramerate = DeviceCapabilityService.getMaxFramerate();
    final presetEncoding = preset?.encoding;
    
    int finalBitrate = presetEncoding?.maxBitrate ?? deviceMaxBitrate;
    int finalFramerate = presetEncoding?.maxFramerate ?? deviceMaxFramerate;
    
    if (_isUltraHQMode) {
      // Android Ultra-HQ mode: Prefer preset target, then fall back to device caps.
      if (presetEncoding != null) {
        finalBitrate = presetEncoding.maxBitrate ?? finalBitrate;
        finalFramerate = presetEncoding.maxFramerate ?? finalFramerate;
      } else {
        finalBitrate = _supports60fps() ? 10_000_000 : 8_000_000;
        if (_supports60fps()) finalFramerate = 60;
      }
    } else {
      // Standard mode: Respect preset and clamp to device + network conditions.
      final networkCap = _networkService.getRecommendedVideoBitrate();
      if (networkCap > 0) {
        finalBitrate = finalBitrate.clamp(1_000_000, networkCap);
      }
      finalBitrate = finalBitrate.clamp(1_000_000, deviceMaxBitrate);
    }
    finalBitrate = finalBitrate.clamp(1_000_000, deviceMaxBitrate);
    finalFramerate = finalFramerate.clamp(10, deviceMaxFramerate);
    
    final callTypeLabel = (_currentCallType == CallType.mixedUnknown && remoteParticipants.isEmpty)
        ? 'pending'
        : _currentCallType.toString();
    debugPrint('🎥 FaceTime-Quality Encoding:');
    debugPrint('   📞 Call Type: $callTypeLabel');
    debugPrint('   🚀 Ultra-HQ Mode: $_isUltraHQMode');
    debugPrint('   📡 Codec: $_currentVideoCodec');
    debugPrint('   📊 Bitrate: ${finalBitrate / 1000000} Mbps');
    debugPrint('   🎬 FPS: $finalFramerate');
    
    // If Safari PWA, enforce conservative cap
    if (_isSafariPwa) {
      return _getSafariPwaEncoding();
    }

    return VideoEncoding(
      maxBitrate: finalBitrate,
      maxFramerate: finalFramerate,
    );
  }

  QualityTier _determineTargetQualityTier(CallStats stats) {
    // Allow all platforms to reach ultra quality if conditions are met
    // Safari PWA will naturally downgrade if it can't handle it

    if (!_networkService.isHighBandwidthConnection()) {
      _qualityUpgradeGateStart = null;
      return QualityTier.high;
    }

    final packetLoss = stats.videoPacketLoss;
    final rttMs = stats.roundTripTime * 1000.0;
    final jitterMs = stats.jitter * 1000.0;

    if (packetLoss >= 8.0 || rttMs >= 450.0 || jitterMs >= 80.0) {
      _qualityUpgradeGateStart = null;
      return QualityTier.medium;
    }
    if (packetLoss >= 4.0 || rttMs >= 300.0 || jitterMs >= 50.0) {
      _qualityUpgradeGateStart = null;
      return QualityTier.high;
    }

    // On web/PWA, allow ultra quality based on network conditions alone
    // On Android, require hardware capability
    if (!kIsWeb && !_supports1440p60() && !_supports4K()) {
      _qualityUpgradeGateStart = null;
      return QualityTier.high;
    }

    final avgSendBitrate = _getAverageSendBitrate();
    final baselineTarget = FaceTimeVideoPresets.h1080.encoding?.maxBitrate ?? 0;
    if (baselineTarget > 0 && avgSendBitrate < baselineTarget * 0.5) {
      _qualityUpgradeGateStart = null;
      return QualityTier.high;
    }

    final avgAvailableOutgoing = _getAverageAvailableOutgoingBitrate();
    if (avgAvailableOutgoing > 0 && avgAvailableOutgoing < 6_000_000) {
      _qualityUpgradeGateStart = null;
      return QualityTier.medium;
    }
    if (avgAvailableOutgoing > 0 && avgAvailableOutgoing < 12_000_000) {
      _qualityUpgradeGateStart = null;
      return QualityTier.high;
    }

    // Ultra upgrade gate: require excellent conditions sustained
    if (packetLoss < 0.5 && rttMs < 80.0 && jitterMs < 10.0) {
      final now = DateTime.now();
      _qualityUpgradeGateStart ??= now;
      final elapsed = now.difference(_qualityUpgradeGateStart!);
      if (elapsed >= const Duration(seconds: 10)) {
        return QualityTier.ultra;
      }
    } else {
      _qualityUpgradeGateStart = null;
    }

    return QualityTier.high;
  }

  VideoParameters _selectPresetForTier(QualityTier tier) {
    switch (tier) {
      case QualityTier.low:
        return FaceTimeVideoPresets.h720Emergency;
      case QualityTier.medium:
        return FaceTimeVideoPresets.h720LowFps;
      case QualityTier.ultra:
        // On web/PWA, use 1440p preset; on Android, use 1440p60 if supported
        if (kIsWeb) {
          return FaceTimeVideoPresets.h1440;
        }
        return _supports1440p60()
            ? FaceTimeVideoPresets.androidExtreme1440p60
            : FaceTimeVideoPresets.h1440;
      case QualityTier.high:
        return _selectCapturePreset();
    }
  }

  void _recordSendBitrate(double bitrate) {
    if (bitrate <= 0) return;
    _recentSendBitrates.add(bitrate);
    if (_recentSendBitrates.length > 12) {
      _recentSendBitrates.removeAt(0);
    }
  }

  void _recordAvailableOutgoingBitrate(double bitrate) {
    if (bitrate <= 0) return;
    _recentAvailableOutgoingBitrates.add(bitrate);
    if (_recentAvailableOutgoingBitrates.length > 12) {
      _recentAvailableOutgoingBitrates.removeAt(0);
    }
  }

  double _getAverageSendBitrate() {
    if (_recentSendBitrates.isEmpty) return 0.0;
    final sum = _recentSendBitrates.fold<double>(0.0, (a, b) => a + b);
    return sum / _recentSendBitrates.length;
  }

  double _getAverageAvailableOutgoingBitrate() {
    if (_recentAvailableOutgoingBitrates.isEmpty) return 0.0;
    final sum = _recentAvailableOutgoingBitrates.fold<double>(0.0, (a, b) => a + b);
    return sum / _recentAvailableOutgoingBitrates.length;
  }

  Future<void> _maybeAdjustCaptureQualityForStats(CallStats stats) async {
    if (_room == null || _localVideoTrack == null) return;
    if (_isSafariPwa) return;

    _recordSendBitrate(stats.videoSendBitrate);
    _recordAvailableOutgoingBitrate(stats.availableOutgoingBitrate);
    final targetTier = _determineTargetQualityTier(stats);
    if (targetTier == _currentQualityTier) return;

    final now = DateTime.now();
    if (_lastQualityTierChange != null &&
        now.difference(_lastQualityTierChange!) < const Duration(seconds: 15)) {
      return;
    }

    if (targetTier.index < _currentQualityTier.index) {
      _qualityUpshiftStart = null;
      _qualityDownshiftStart ??= now;
      if (now.difference(_qualityDownshiftStart!) < const Duration(seconds: 15)) {
        return;
      }
    } else {
      _qualityDownshiftStart = null;
      _qualityUpshiftStart ??= now;
      if (now.difference(_qualityUpshiftStart!) < const Duration(seconds: 10)) {
        return;
      }
    }

    _currentQualityTier = targetTier;
    _lastQualityTierChange = now;
    _qualityDownshiftStart = null;
    _qualityUpshiftStart = null;

    final preset = _selectPresetForTier(targetTier);
    await _recreateAndPublishVideoTrack(preset);
    debugPrint('🎯 Quality tier switched to ${targetTier.name}');
  }

  // Upgrade gate state (Android-only)
  DateTime? _upgradeGateStart;
  bool _upgradePerformed = false;

  /// Monitor stats to perform a safe one-time upgrade on Android when conditions are excellent
  void _maybePerformUpgradeGate(CallStats stats) {
    if (_upgradePerformed) return;
    if (!DeviceModeService.isAndroidNative()) return; // Safari PWA never upgrades
    // Require app foreground, no reconnects, low packet loss, low RTT, low jitter
    final packetLoss = stats.videoPacketLoss;
    final rttMs = stats.roundTripTime * 1000.0;
    final jitterMs = stats.jitter * 1000.0;
    if (packetLoss > 0.5 || rttMs >= 150.0 || jitterMs >= 10.0 || _isReconnecting) {
      _upgradeGateStart = null;
      return;
    }

    final now = DateTime.now();
    _upgradeGateStart ??= now;
    final elapsed = now.difference(_upgradeGateStart!);
    if (elapsed >= const Duration(seconds: 15)) {
      // Conditions met continuously for 15s — attempt upgrade (safe, single time)
      _performUpgradeTo1080pSafe();
      _upgradePerformed = true;
    }
  }

  Future<void> _performUpgradeTo1080pSafe() async {
    try {
      // Double-check again
      if (!DeviceModeService.isAndroidNative()) return;
      final preset = FaceTimeVideoPresets.h1080;
      final encoding = preset.encoding ?? VideoEncoding(maxBitrate: 8_000_000, maxFramerate: 30);
      // Recreate & publish track with new preset — this is a one-time upgrade per call
      await _recreateAndPublishVideoTrack(preset, maxBitrateOverride: encoding.maxBitrate);
      debugPrint('✅ Performed safe upgrade to 1080p (one-time gate)');
    } catch (e) {
      debugPrint('⚠️ Upgrade gate failed or aborted: $e');
    }
  }

  int _getAdaptiveTargetBitrate(CallStats stats, int baseBitrate) {
    final packetLoss = (stats.videoPacketLoss > stats.audioPacketLoss)
        ? stats.videoPacketLoss
        : stats.audioPacketLoss;
    final rttMs = stats.roundTripTime * 1000.0;
    final jitterMs = stats.jitter * 1000.0;
    final availableOutgoing = stats.availableOutgoingBitrate;

    double factor = 1.0;
    if (packetLoss >= 5.0 || rttMs >= 300.0 || jitterMs >= 40.0) {
      factor = 0.85;  // 15% reduction (gentler)
    } else if (packetLoss >= 2.0 || rttMs >= 200.0 || jitterMs >= 30.0) {
      factor = 0.90;  // 10% reduction
    } else if (packetLoss >= 1.0 || rttMs >= 150.0 || jitterMs >= 20.0) {
      factor = 0.95;  // 5% reduction
    }

    final minBitrate = _getMinBitrateForPreset(_currentCapturePreset) ??
        (_isUltraHQMode ? 6_000_000 : 3_000_000);
    final target = (baseBitrate * factor).round();
    final outgoingCap = availableOutgoing > 0
        ? (availableOutgoing * 0.85).round()
        : null;
    final cap = (outgoingCap != null && outgoingCap < baseBitrate)
        ? outgoingCap
        : baseBitrate;
    return target.clamp(minBitrate, cap);
  }

  int? _getMinBitrateForPreset(VideoParameters? preset) {
    final dims = preset?.dimensions;
    if (dims == null) return null;
    if (dims.width >= 3840) {
      return 12_000_000;
    }
    if (dims.width >= 2560) {
      return 8_000_000;
    }
    if (dims.width >= 1920) {
      return 6_000_000;
    }
    if (dims.width >= 1280) {
      return 3_000_000;
    }
    return 2_000_000;
  }

  bool _shouldEnableSimulcast() {
    if (_isSafariPwa) return false;
    if (!FeatureFlags.enableSimulcastLadder) return false;
    if (kIsWeb && !DeviceCapabilityService.webSupportsSimulcast()) return false;
    // Simulcast is only helpful in multiparty; avoid in 1:1.
    return remoteParticipants.length >= 2;
  }

  Future<void> _applySimulcastPolicyIfNeeded() async {
    final shouldEnable = _shouldEnableSimulcast();
    if (shouldEnable == _isSimulcastEnabled) return;

    final now = DateTime.now();
    if (_lastSimulcastChange != null &&
        now.difference(_lastSimulcastChange!) < const Duration(seconds: 15)) {
      return;
    }
    _lastSimulcastChange = now;
    _isSimulcastEnabled = shouldEnable;

    if (_room == null || _localVideoTrack == null) return;
    final preset = _currentCapturePreset ?? FaceTimeVideoPresets.h720;
    try {
      await _recreateAndPublishVideoTrack(preset);
      debugPrint('🔄 Simulcast ${_isSimulcastEnabled ? "enabled" : "disabled"} based on participant count');
    } catch (e) {
      debugPrint('⚠️ Failed to apply simulcast policy: $e');
    }
  }

  VideoParameters _selectCapturePreset() {
    if (_isUltraHQMode && _supports4K()) {
      return FaceTimeVideoPresets.androidExtreme4K;
    }
    if (_isUltraHQMode && _supports1440p60()) {
      return FaceTimeVideoPresets.androidExtreme1440p60;
    }
    if (_isUltraHQMode && _supports60fps()) {
      return FaceTimeVideoPresets.androidUltraHQ60;
    }
    if (_isUltraHQMode) {
      return FaceTimeVideoPresets.androidUltraHQ;
    }
    switch (_currentCallType) {
      case CallType.androidAndroid:
        return FaceTimeVideoPresets.h1080;
      case CallType.androidIOSPWA:
        return FaceTimeVideoPresets.h1080;
      case CallType.iosPWAIOSPWA:
        return FaceTimeVideoPresets.h1080;
      default:
        return FaceTimeVideoPresets.h1080;
    }
  }
  
  /// Connect to LiveKit room with FaceTime-quality tuning
  Future<bool> connect({
    required String url,
    required String token,
    required String roomName,
  }) async {
    _manualDisconnect = false;
    _abortConnect = false;
    _cancelReconnectTimer();
    _lastUrl = url;
    _lastToken = token;
    _lastRoomName = roomName;
    _reconnectAttempts = 0;
    try {
      _errorMessage = null;
      
      _currentCallType = _classifyCallType();
      _isUltraHQMode = _shouldEnableUltraHQ();
      _currentVideoCodec = _getPreferredCodec();
      // Default simulcast behavior: disable for 1:1 until multiparty detected.
      _isSimulcastEnabled = _shouldEnableSimulcast();
      
      final callTypeLabel = (_currentCallType == CallType.mixedUnknown && remoteParticipants.isEmpty)
          ? 'pending'
          : _currentCallType.toString();
      debugPrint('🎯 FaceTime-Quality Connection Setup:');
      debugPrint('   📞 Call Type: $callTypeLabel');
      debugPrint('   🚀 Ultra-HQ Mode: $_isUltraHQMode');
      debugPrint('   📡 Preferred Codec: $_currentVideoCodec');
      debugPrint('   🔄 Simulcast: $_isSimulcastEnabled (disabled for 1-to-1)');
      
      final urlCandidates = _buildUrlCandidates(url);
      Exception? lastError;

      for (final candidateUrl in urlCandidates) {
        try {
          _room = Room();
          _setupRoomListeners();
          _networkService.startMonitoring();

          VideoParameters captureParams = _selectCapturePreset();
          // Enforce Safari PWA conservative capture preset
          if (_isSafariPwa) {
            captureParams = FaceTimeVideoPresets.h720;
          }
          _currentCapturePreset = captureParams;
          final optimalEncoding = _getOptimalVideoEncoding(captureParams);

        final processor = null;

      await _room!.connect(
        candidateUrl,
        token,
        connectOptions: ConnectOptions(
          autoSubscribe: true,
          rtcConfiguration: _buildRtcConfiguration(),
        ),
        roomOptions: RoomOptions(
          defaultCameraCaptureOptions: CameraCaptureOptions(
            maxFrameRate: (optimalEncoding.maxFramerate ?? 30).toDouble(),
            params: captureParams,
            processor: processor,
          ),
              // Screen share removed: no default screen-share capture options.
              defaultAudioCaptureOptions: AudioCaptureOptions(
                echoCancellation: true,
                noiseSuppression: true,
                autoGainControl: true,
              ),
              defaultVideoPublishOptions: VideoPublishOptions(
                    videoEncoding: optimalEncoding,
                    simulcast: _isSimulcastEnabled,
                    videoCodec: _getPublishVideoCodec(),
                    backupVideoCodec: _getPublishVideoCodec() == 'av1'
                        ? const BackupVideoCodec(codec: 'h264', simulcast: true)
                        : VideoPublishOptions.defualtBackupVideoCodec,
                    // maintainResolution keeps the picture sharp; only framerate
                    // is sacrificed under congestion — same as Apple FaceTime.
                    degradationPreference: DegradationPreference.maintainResolution,
                  ),
              defaultAudioPublishOptions: AudioPublishOptions(
                audioBitrate: _getOptimalAudioBitrate(),
                dtx: true,
                red: true,
              ),
              adaptiveStream: true,
              dynacast: true,
            ),
          );

          _lastUrl = candidateUrl;
          _isReconnecting = false;
          _reconnectAttempts = 0;
          lastError = null;
          break;
        } catch (e) {
          lastError = Exception(e.toString());
          await _room?.disconnect();
          _networkService.stopMonitoring();
          _room = null;
        }
      }

      if (lastError != null && _room == null) {
        throw lastError;
      }

      if (_manualDisconnect || _abortConnect) {
        await _room?.disconnect();
        _room = null;
        _networkService.stopMonitoring();
        return false;
      }

      await Future.wait([
        enableCamera(),
        enableMicrophone(),
      ]).timeout(const Duration(seconds: 12), onTimeout: () {
        throw Exception('Timed out while enabling local media tracks');
      });
      
      // Verify actual codec being used after connection
      await Future.delayed(const Duration(seconds: 2)); // Wait for negotiation
      await _logActualCodecUsed();
      
      debugPrint('✅ Connected to LiveKit room with FaceTime-quality tuning: $roomName');
      return true;
    } catch (e) {
      _errorMessage = 'Failed to connect: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }
  
  /// Get optimal audio bitrate.
  /// Opus at 24–32 kbps is intelligible, but 64 kbps delivers the natural,
  /// full-bandwidth voice quality that FaceTime and Zoom target. Audio
  /// consumes <5% of total bandwidth at 64 kbps so it doesn't starve video.
  int _getOptimalAudioBitrate() {
    switch (_currentCallType) {
      case CallType.androidAndroid:
        return _isUltraHQMode ? 64000 : 56000; // 64 kbps / 56 kbps
      case CallType.androidIOSPWA:
        return 56000; // 56 kbps
      default:
        return 48000; // 48 kbps minimum — clear improvement over 24 kbps
    }
  }

  AudioCaptureOptions _buildAudioCaptureOptions() {
    if (_customAudioCaptureOptions != null) {
      return _customAudioCaptureOptions!;
    }
    return const AudioCaptureOptions(
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
    );
  }

  /// Update audio capture options and apply if microphone is active
  Future<void> updateAudioCaptureOptions(AudioCaptureOptions options) async {
    _customAudioCaptureOptions = options;
    if (isMicrophoneEnabled) {
      await recoverAudio(forceRecreate: true);
    }
  }
  
  /// Disconnect from room and cleanup
  Future<void> disconnect() async {
    try {
      debugPrint('🔌 Disconnecting from LiveKit...');
      _manualDisconnect = true;
      _abortConnect = true;
      _cancelReconnectTimer();
      _isReconnecting = false;
      _networkService.stopMonitoring();
      _pipService.dispose();
      _internalStatsService?.stopCollecting();
      
      await Future.wait([
        _localVideoTrack?.stop() ?? Future.value(),
        _localAudioTrack?.stop() ?? Future.value(),
      ]).timeout(const Duration(seconds: 3), onTimeout: () {
        debugPrint('⚠️ Timeout stopping local tracks');
        return <void>[];
      });
      
      await _room?.disconnect().timeout(const Duration(seconds: 3), onTimeout: () {
        debugPrint('⚠️ Timeout disconnecting from room');
      });
      
      _localVideoTrack = null;
      _localAudioTrack = null;
      _room = null;
      _internalStatsService = null;
      _isUltraHQMode = false;
      _isSimulcastEnabled = false;
      _reconnectAttempts = 0;
      // Reset upgrade gate so the 1080p/quality upgrade can fire again on reconnect.
      _upgradePerformed = false;
      _upgradeGateStart = null;
      _qualityUpgradeGateStart = null;
      _qualityDownshiftStart = null;
      _qualityUpshiftStart = null;
      _recentSendBitrates.clear();
      _recentAvailableOutgoingBitrates.clear();
      
      debugPrint('✅ LiveKit disconnected successfully');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error disconnecting: $e');
      _localVideoTrack = null;
      _localAudioTrack = null;
      _room = null;
      _internalStatsService = null;
      notifyListeners();
    }
  }
  
  /// Enable camera with FaceTime-quality settings
  Future<void> enableCamera() async {
    try {
      debugPrint('📹 enableCamera() called with FaceTime-quality settings');
      if (_room == null) {
        debugPrint('❌ Room is null, cannot enable camera');
        return;
      }
      
      if (_localVideoTrack == null) {
        debugPrint('📹 Creating camera track with FaceTime-quality preset...');
        
        VideoParameters captureParams = _selectCapturePreset();
        if (_isSafariPwa) captureParams = FaceTimeVideoPresets.h720;
        final optimalEncoding = _getOptimalVideoEncoding(captureParams);
        
        debugPrint('📹 FaceTime-quality capture params:');
        debugPrint('   📐 Resolution: ${captureParams.dimensions.width}x${captureParams.dimensions.height}');
        final encoding = captureParams.encoding;
        final bitrate = encoding?.maxBitrate ?? 6000000;
        final framerate = encoding?.maxFramerate ?? 30;
        debugPrint('   📊 Max Bitrate: ${bitrate / 1000000} Mbps');
        debugPrint('   🎬 Max FPS: $framerate');
        
        final processor = null;

        _localVideoTrack = await LocalVideoTrack.createCameraTrack(
          CameraCaptureOptions(
            maxFrameRate: (optimalEncoding.maxFramerate ?? 30).toDouble(),
            params: captureParams,
            processor: processor,
          ),
        );
        _currentCapturePreset = captureParams;
        
        debugPrint('📤 Publishing video track with FaceTime-quality encoding...');
        await _room!.localParticipant?.publishVideoTrack(
          _localVideoTrack!,
          publishOptions: _buildVideoPublishOptions(optimalEncoding),
        );
        debugPrint('✅ FaceTime-quality video track published');
      }
      
      await _localVideoTrack?.unmute();
      debugPrint('✅ Video track unmuted');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to enable camera: $e');
      // MediaPipe removed - no per-frame processing errors
      _errorMessage = 'Failed to enable camera: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Apply bitrate & adaptation policy (From brief)
  Future<void> _maybeAdjustVideoForStats(CallStats stats) async {
    if (!_adaptiveBitrateEnabled) return;
    if (_room == null || _localVideoTrack == null) return;

    final baseEncoding = _getOptimalVideoEncoding(_currentCapturePreset);
    final baseBitrate = baseEncoding.maxBitrate ?? 0;
    if (baseBitrate <= 0) return;

    final targetBitrate = _getAdaptiveTargetBitrate(stats, baseBitrate);
    if (_currentAdaptiveBitrate == targetBitrate) return;

    final now = DateTime.now();
    if (_lastAdaptiveChange != null &&
        now.difference(_lastAdaptiveChange!) < const Duration(seconds: 3)) {
      return;
    }

    final previous = _currentAdaptiveBitrate ?? baseBitrate;
    final changeRatio = (targetBitrate - previous).abs() / previous;
    if (changeRatio < 0.1) return;

    if (targetBitrate < previous) {
      _qualityDownshiftStart ??= now;
      if (now.difference(_qualityDownshiftStart!) < const Duration(seconds: 12)) {
        return;
      }
    } else {
      _qualityDownshiftStart = null;
    }

    final preset = _currentCapturePreset ?? FaceTimeVideoPresets.h720;
    final processor = null;

    debugPrint('📉 Adaptive bitrate request: ${previous / 1000000} → ${targetBitrate / 1000000} Mbps');
    // Try setParameters (encoder parameter update) first — prefer no track recreate
    try {
      final trackDyn = _localVideoTrack as dynamic;
      // Best-effort API: many platform SDKs expose a setParameters/setEncodingParameters
      // that accepts a map with maxBitrate/maxFramerate. Use dynamic call so it
      // won't break on platforms where it's not supported.
      final paramObj = {
        'maxBitrate': targetBitrate,
        'maxFramerate': (baseEncoding.maxFramerate ?? 30),
      };
      final res = await trackDyn.setParameters(paramObj);
      if (res == null || res == true) {
        debugPrint('✅ Applied encoder parameter update (no track recreate)');
        _currentAdaptiveBitrate = targetBitrate;
        _lastAdaptiveChange = now;
        return;
      }
      debugPrint('⚠️ setParameters returned falsey — falling back to recreate');
    } catch (e) {
      debugPrint('⚠️ setParameters not available or failed: $e — will recreate track');
    }

    // Fallback: recreate track (ensure UI is notified so preview rebinds)
    debugPrint('📉 Performing safe recreate to apply bitrate: ${targetBitrate / 1000000} Mbps');
    await _recreateAndPublishVideoTrack(
      preset,
      maxBitrateOverride: targetBitrate,
      processor: processor,
    );
    _currentAdaptiveBitrate = targetBitrate;
    _lastAdaptiveChange = now;
  }

  /// Recreate and publish local camera track
  Future<void> _recreateAndPublishVideoTrack(
    VideoParameters preset, {
    int? maxBitrateOverride,
    TrackProcessor<VideoProcessorOptions>? processor,
  }) async {
    try {
      final wasMuted = !isCameraEnabled;
      final localParticipant = _room?.localParticipant;
      final oldTrack = _localVideoTrack;

      if (localParticipant != null && oldTrack != null) {
        final oldPub = localParticipant.getTrackPublicationBySource(TrackSource.camera);
        if (oldPub != null) {
          await localParticipant.removePublishedTrack(oldPub.sid);
        }
      }

      await oldTrack?.stop();

      final optimalEncoding = _getOptimalVideoEncoding(preset);
      final encoding = maxBitrateOverride != null 
        ? VideoEncoding(
            maxBitrate: maxBitrateOverride,
            maxFramerate: optimalEncoding.maxFramerate,
          )
        : optimalEncoding;

      _localVideoTrack = await LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(
          maxFrameRate: (encoding.maxFramerate ?? 30).toDouble(),
          params: preset,
          processor: processor,
        ),
      );
      _currentCapturePreset = preset;

      await localParticipant?.publishVideoTrack(
        _localVideoTrack!,
        publishOptions: _buildVideoPublishOptions(encoding),
      );

      if (wasMuted) {
        await _localVideoTrack?.mute();
      } else {
        await _localVideoTrack?.unmute();
      }
      
      debugPrint('🔁 Recreated video track with FaceTime-quality preset');
      // Notify UI so any renderer bindings rebind to the new LocalVideoTrack
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to recreate video track: $e');
      if (processor != null) {
        _mediaPipeError = 'MediaPipe failed to apply. Effects are disabled.';
        notifyListeners();
      }
    }
  }

  /// External entrypoint: apply observed stats
  Future<void> applyObservedStats(CallStats stats) async {
    _networkService.updateFromCallStats(stats);
    await _maybeAdjustVideoForStats(stats);
    try {
      await _maybeAdjustCaptureQualityForStats(stats);
    } catch (_) {}
  }

  /// Apply a high-level capture profile
  Future<void> applyCaptureProfile(CaptureProfile profile) async {
    try {
      if (_room == null) return;

      VideoParameters preset;
      
      switch (profile) {
        case CaptureProfile.low:
          preset = FaceTimeVideoPresets.h720;
          break;
        case CaptureProfile.medium:
          preset = _isUltraHQMode ? FaceTimeVideoPresets.androidUltraHQ720 : FaceTimeVideoPresets.h720;
          break;
        case CaptureProfile.high:
          preset = _isUltraHQMode ? FaceTimeVideoPresets.androidUltraHQ : FaceTimeVideoPresets.h1080;
          break;
      }

      await _recreateAndPublishVideoTrack(preset);
    } catch (e) {
      debugPrint('applyCaptureProfile error: $e');
    }
  }
  
  /// Disable camera (mute video track)
  Future<void> disableCamera() async {
    try {
      await _localVideoTrack?.mute();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to disable camera: ${e.toString()}';
      notifyListeners();
    }
  }
  
  /// Enable microphone with optimized audio settings
  Future<void> enableMicrophone() async {
    try {
      if (_room == null) return;
      
      if (_localAudioTrack == null) {
        _localAudioTrack = await LocalAudioTrack.create(
          _buildAudioCaptureOptions(),
        );
        
        // Explicitly unmute immediately after creation
        await _localAudioTrack!.unmute();
        
        await _room!.localParticipant?.publishAudioTrack(
          _localAudioTrack!,
          publishOptions: AudioPublishOptions(
            audioBitrate: _getOptimalAudioBitrate(),
            dtx: true,
            red: true,
          ),
        );
      }
      
      // Ensure unmuted
      await _localAudioTrack?.unmute();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to enable microphone: ${e.toString()}';
      notifyListeners();
    }
  }
  
  /// Disable microphone (mute audio track)
  Future<void> disableMicrophone() async {
    try {
      await _localAudioTrack?.mute();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to disable microphone: ${e.toString()}';
      notifyListeners();
    }
  }
  
  /// Toggle microphone state
  Future<void> toggleMicrophone() async {
    if (isMicrophoneEnabled) {
      await disableMicrophone();
    } else {
      await enableMicrophone();
      if (!isMicrophoneEnabled) {
        await recoverAudio(forceRecreate: true);
      }
    }
  }

  Future<void> recoverAudio({bool forceRecreate = false}) async {
    if (_isRecoveringAudio) return;
    final room = _room;
    if (room == null) return;

    _isRecoveringAudio = true;
    try {
      final localParticipant = room.localParticipant;
      if (localParticipant == null) return;

      final audioPub = localParticipant.getTrackPublicationBySource(TrackSource.microphone);

      if (forceRecreate || audioPub == null) {
        if (audioPub != null) {
          await localParticipant.removePublishedTrack(audioPub.sid);
        }
        _localAudioTrack = await LocalAudioTrack.create(_buildAudioCaptureOptions());
        await localParticipant.publishAudioTrack(
          _localAudioTrack!,
          publishOptions: AudioPublishOptions(
            audioBitrate: _getOptimalAudioBitrate(),
            dtx: true,
            red: true,
          ),
        );
      } else {
        await localParticipant.setMicrophoneEnabled(
          true,
          audioCaptureOptions: _buildAudioCaptureOptions(),
        );
      }

      await _localAudioTrack?.unmute();

      for (final participant in room.remoteParticipants.values) {
        for (final pub in participant.audioTrackPublications) {
          if ((!pub.subscribed || pub.track == null)) {
            try {
              await pub.subscribe();
            } catch (e) {
              debugPrint('⚠️ Failed to resubscribe audio: $e');
            }
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ Audio recovery failed: $e');
    } finally {
      _isRecoveringAudio = false;
    }
  }
  
  /// Toggle camera state
  Future<void> toggleCamera() async {
    if (isCameraEnabled) {
      await disableCamera();
    } else {
      await enableCamera();
    }
  }
  
  /// Switch between front and back camera with camera control enhancements
  Future<void> switchCamera() async {
    try {
      final track = _localVideoTrack;
      if (track == null) {
        debugPrint('❌ Cannot switch camera: no active video track');
        return;
      }
      
      _currentCameraPosition = (_currentCameraPosition == CameraPosition.front)
          ? CameraPosition.back
          : CameraPosition.front;
      
      // Camera Control enhancements from brief:
      // * Lock exposure after stabilization
      // * Lock focus after autofocus completes
      // * Avoid camera restarts mid-call
      
      await track.setCameraPosition(_currentCameraPosition);
      
      debugPrint('✅ Camera switched to: $_currentCameraPosition with FaceTime-quality controls');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Camera switch error: $e');
      _errorMessage = 'Failed to switch camera: ${e.toString()}';
      notifyListeners();
    }
  }
  
  /// Set up room event listeners
  void _setupRoomListeners() {
    if (_room == null) return;
    
    _room!.addListener(_onRoomDidUpdate);
    
    _room!.createListener()
      ..on<RoomReconnectingEvent>((event) {
        _isReconnecting = true;
        debugPrint('🔄 Room reconnecting...');
        notifyListeners();
      })
      ..on<RoomReconnectedEvent>((event) {
        _isReconnecting = false;
        _reconnectAttempts = 0;
        debugPrint('✅ Room reconnected');
        unawaited(recoverAudio());
        notifyListeners();
      })
      ..on<RoomAttemptReconnectEvent>((event) {
        debugPrint('🔁 Reconnect attempt ${event.attempt}/${event.maxAttemptsRetry} '
            'next in ${event.nextRetryDelaysInMs}ms');
      })
      ..on<RoomDisconnectedEvent>((event) {
        debugPrint('🔌 Room disconnected: ${event.reason}');
        final shouldReconnect = _shouldAttemptReconnect(event.reason);
        if (shouldReconnect) {
          _scheduleReconnect();
        }
        _stopAndUnpublishLocalTracks();
        _room = null;
        _isUltraHQMode = false;
        _isSimulcastEnabled = false;
        notifyListeners();
      })
      ..on<ParticipantConnectedEvent>((event) {
        debugPrint('👤 Participant connected: ${event.participant.identity}');
        debugPrint('   - Call type may have changed, reclassifying...');
        final updatedCallType = _classifyCallType();
        if (updatedCallType != _currentCallType) {
          _currentCallType = updatedCallType;
          _isUltraHQMode = _shouldEnableUltraHQ();
          if (_room != null && _localVideoTrack != null) {
            unawaited(_recreateAndPublishVideoTrack(_selectCapturePreset()));
          }
        }
        unawaited(_applySimulcastPolicyIfNeeded());
        debugPrint('   📞 New Call Type: $_currentCallType');
        debugPrint('   🚀 Ultra-HQ Mode: $_isUltraHQMode');
        notifyListeners();
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        debugPrint('👋 Participant disconnected: ${event.participant.identity}');
        unawaited(_applySimulcastPolicyIfNeeded());
        notifyListeners();
      })
      ..on<TrackPublishedEvent>((event) {
        debugPrint('📢 Track published: ${event.publication.sid} by ${event.participant.identity}');
        notifyListeners();
      })
      ..on<TrackSubscribedEvent>((event) async {
        debugPrint('✅ Track subscribed: ${event.track.sid}');
        debugPrint('   - Kind: ${event.track.kind}');
        debugPrint('   - Participant: ${event.participant.identity}');
        debugPrint('   - Muted: ${event.track.muted}');
        
        // Start tracks immediately after subscription
        if (event.track.kind == TrackType.AUDIO) {
          final audioTrack = event.track as RemoteAudioTrack;
          await audioTrack.start();
          // Remote tracks cannot be unmuted locally - sender controls mute state
          debugPrint('   🔊 Remote audio track started');
        } else if (event.track.kind == TrackType.VIDEO) {
          final videoTrack = event.track as RemoteVideoTrack;
          await videoTrack.start();
          // Remote tracks cannot be unmuted locally - sender controls mute state
          debugPrint('   📹 Remote video track started');
        }
        
        notifyListeners();
      })
      ..on<TrackUnpublishedEvent>((event) {
        debugPrint('Track unpublished: ${event.publication.sid}');
        notifyListeners();
      });
  }

  // MediaPipe removed: no per-frame processing handler required.
  
  void _onRoomDidUpdate() {
    notifyListeners();
  }
  
  /// Verify hardware encoder is being used
  Future<bool> _verifyHardwareEncoder() async {
    try {
      final stats = await collectCallStats();
      final codec = stats.videoCodec.toLowerCase();
      
      // Check for hardware encoder indicators
      final isHardware = codec.contains('hardware') ||
          codec.contains('qcom') ||      // Qualcomm
          codec.contains('exynos') ||    // Samsung
          codec.contains('mtk') ||       // MediaTek
          codec.contains('kirin') ||     // Huawei
          codec.contains('videotoolbox'); // Apple
      
      if (!isHardware && codec.isNotEmpty && codec != 'unknown') {
        debugPrint('⚠️ Software encoder detected: $codec');
        debugPrint('   This may cause performance issues and battery drain');
      }
      
      return isHardware;
    } catch (e) {
      debugPrint('⚠️ Could not verify encoder type: $e');
      return false;
    }
  }

  /// Log actual codec being used after connection
  Future<void> _logActualCodecUsed() async {
    try {
      final localParticipant = _room?.localParticipant;
      final videoTrack = localParticipant?.videoTrackPublications.firstOrNull?.track;
      
      if (videoTrack != null) {
        final stats = await collectCallStats();
        final hasCodec = stats.videoCodec.isNotEmpty && stats.videoCodec != 'unknown';
        final hasResolution = stats.videoResolution != 'N/A';
        debugPrint('📊 ACTUAL MEDIA STATS:');
        debugPrint('   🎯 Requested: $_currentVideoCodec');
        if (hasCodec || hasResolution || stats.videoFps > 0) {
          debugPrint('   ✅ Video codec: ${stats.videoCodec}');
          debugPrint('   ✅ Resolution: ${stats.videoResolution}');
          debugPrint('   ✅ FPS: ${stats.videoFps}');
          debugPrint('   ✅ Send bitrate: ${stats.videoSendBitrateFormatted}');
          debugPrint('   ✅ Recv bitrate: ${stats.videoRecvBitrateFormatted}');
          debugPrint('   ✅ Audio codec: ${stats.audioCodec}');
          debugPrint('   ✅ Audio send: ${stats.audioSendBitrateFormatted}');
          debugPrint('   ✅ Audio recv: ${stats.audioRecvBitrateFormatted}');
          
          // Verify hardware encoding
          await _verifyHardwareEncoder();
        } else if (kDebugMode) {
          debugPrint('   ℹ️ Codec stats not available yet; waiting for stats events');
        }
      } else {
        debugPrint('⚠️ Could not verify codec - no video track found');
      }
    } catch (e) {
      debugPrint('Error checking actual codec: $e');
    }
  }

  Future<void> _stopAndUnpublishLocalTracks() async {
    try {
      final localParticipant = _room?.localParticipant;
      if (localParticipant != null) {
        final videoPub = localParticipant.getTrackPublicationBySource(TrackSource.camera);
        final audioPub = localParticipant.getTrackPublicationBySource(TrackSource.microphone);
        if (videoPub != null) {
          await localParticipant.removePublishedTrack(videoPub.sid);
        }
        if (audioPub != null) {
          await localParticipant.removePublishedTrack(audioPub.sid);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to unpublish local tracks: $e');
    }

    try {
      await _localVideoTrack?.stop();
      await _localAudioTrack?.stop();
    } catch (e) {
      debugPrint('⚠️ Failed to stop local tracks: $e');
    } finally {
      _localVideoTrack = null;
      _localAudioTrack = null;
    }
  }

  /// Debug FaceTime-quality settings
  void debugFaceTimeQualitySettings() {
    debugPrint('🔍 FaceTime-Quality Debug Info:');
    debugPrint('   📞 Call Type: $_currentCallType');
    debugPrint('   🚀 Ultra-HQ Mode: $_isUltraHQMode');
    debugPrint('   📡 Codec: $_currentVideoCodec');
    debugPrint('   🔄 Simulcast: $_isSimulcastEnabled');
    debugPrint('   🌐 Platform: ${kIsWeb ? "Web/PWA" : Platform.operatingSystem}');
    debugPrint('   📊 Network Type: ${_networkService.getCurrentNetworkType()}');
    
    if (kIsWeb) {
      debugPrint('   ⚠️ iOS PWA Constraints: Safari WebRTC limitations apply');
      debugPrint('   - May cap bitrate unpredictably');
      debugPrint('   - May ignore some encoder hints');
      debugPrint('   - May throttle under thermal pressure');
    }
    
    // Check actual codec being used
    _logActualCodecUsed();
  }

  RTCConfiguration _buildRtcConfiguration() {
    final iceServers = _parseIceServers() ?? _defaultIceServers();
    if (iceServers.isEmpty) {
      debugPrint('⚠️ No ICE servers configured. TURN is required for reliable NAT traversal.');
    } else if (!IceServerConfig.isConfigured) {
      debugPrint('⚠️ Using STUN-only fallback ICE servers. Configure TURN for reliability.');
    }
    return RTCConfiguration(
      iceServers: iceServers,
      iceTransportPolicy:
          Environment.liveKitForceRelay ? RTCIceTransportPolicy.relay : null,
    );
  }

  List<RTCIceServer>? _parseIceServers() {
    final raw = IceServerConfig.iceServersJson.trim();
    if (raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;

      final servers = <RTCIceServer>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final rawUrls = entry['urls'];
        final urls = rawUrls is List
            ? rawUrls.map((e) => e.toString()).toList()
            : rawUrls is String
                ? [rawUrls]
                : null;
        final username = entry['username']?.toString();
        final credential = entry['credential']?.toString();
        if (urls == null || urls.isEmpty) {
          continue;
        }
        servers.add(RTCIceServer(
          urls: urls,
          username: username,
          credential: credential,
        ));
      }
      return servers.isEmpty ? null : servers;
    } catch (e) {
      debugPrint('⚠️ Failed to parse LIVEKIT_ICE_SERVERS_JSON: $e');
      return null;
    }
  }

  List<RTCIceServer> _defaultIceServers() {
    // STUN-only fallback to avoid empty ICE config; TURN strongly recommended.
    return const [
      RTCIceServer(urls: ['stun:stun.l.google.com:19302']),
      RTCIceServer(urls: ['stun:stun1.l.google.com:19302']),
    ];
  }

  List<String> _buildUrlCandidates(String primaryUrl) {
    final candidates = <String>[];
    void addUrl(String? url) {
      final trimmed = url?.trim();
      if (trimmed == null || trimmed.isEmpty) return;
      if (!candidates.contains(trimmed)) candidates.add(trimmed);
    }

    addUrl(primaryUrl);
    addUrl(Environment.liveKitUrl);
    for (final url in Environment.liveKitFallbackUrls.split(',')) {
      addUrl(url);
    }

    return candidates;
  }

  bool _shouldAttemptReconnect(DisconnectReason? reason) {
    if (_manualDisconnect) return false;
    switch (reason) {
      case DisconnectReason.clientInitiated:
      case DisconnectReason.duplicateIdentity:
      case DisconnectReason.participantRemoved:
      case DisconnectReason.roomDeleted:
      case DisconnectReason.serverShutdown:
        return false;
      default:
        return _lastUrl != null && _lastToken != null && _lastRoomName != null;
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;
    if (_lastUrl == null || _lastToken == null || _lastRoomName == null) return;

    _reconnectAttempts++;
    final delaySeconds = _reconnectAttempts <= 1
        ? 2
        : (_reconnectAttempts * _reconnectAttempts).clamp(2, 30);

    _isReconnecting = true;
    debugPrint('⏳ Scheduling reconnect in ${delaySeconds}s');
    notifyListeners();

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      _reconnectTimer = null;
      if (_manualDisconnect) return;
      await connect(
        url: _lastUrl!,
        token: _lastToken!,
        roomName: _lastRoomName!,
      );
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }
  
  /// Update the PiP video stream with the specified participant's video track
  Future<void> updatePipStream(VideoTrack? track) async {
    if (!kIsWeb) return;
    
    try {
      final mediaStream = WebPipBridge.getMediaStreamFromTrack(track);
      if (mediaStream != null) {
        _pipService.updateStream(mediaStream);
        debugPrint('✅ Updated PiP stream for main participant');
      } else {
        debugPrint('⚠️ Could not extract MediaStream from track');
      }
    } catch (e) {
      debugPrint('❌ Failed to update PiP stream: $e');
    }
  }
  
  /// Setup auto PiP when user switches tabs (web only)
  void setupAutoPip() {
    if (!kIsWeb) return;
    // Do not enable PiP in Safari PWA (unreliable on iOS PWA)
    if (_isSafariPwa) return;
    _pipService.setupAutoEnterPip();
  }
  
  @override
  void dispose() {
    // MediaPipe removed - no listener to remove
    disconnect();
    super.dispose();
  }
}
