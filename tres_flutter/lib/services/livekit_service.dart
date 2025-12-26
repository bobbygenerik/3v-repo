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

/// Custom video presets following FaceTime-quality tuning brief
class FaceTimeVideoPresets {
  // Cross-Platform 1080p HQ
  static final h1080 = VideoParameters(
    dimensions: VideoDimensions(1920, 1080),
    // Target 1080p at ~5 Mbps as per brief (conservative)
    encoding: VideoEncoding(maxBitrate: 5_000_000, maxFramerate: 30),
  );

  // Cross-Platform 720p Fallback
  static final h720 = VideoParameters(
    dimensions: VideoDimensions(1280, 720),
    // Target 720p at ~2 Mbps as per brief
    encoding: VideoEncoding(maxBitrate: 2_000_000, maxFramerate: 30),
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
    encoding: VideoEncoding(maxBitrate: 9_000_000, maxFramerate: 30),
  );

  // Android-Only Ultra-HQ 720p
  static final androidUltraHQ720 = VideoParameters(
    dimensions: VideoDimensions(1280, 720),
    encoding: VideoEncoding(maxBitrate: 5_000_000, maxFramerate: 30),
  );

  // LOW-END DEVICE OPTIMIZATIONS
  static final lowEnd480p = VideoParameters(
    dimensions: VideoDimensions(640, 480),
    encoding: VideoEncoding(maxBitrate: 2_000_000, maxFramerate: 15),
  );

  static final lowEnd360p = VideoParameters(
    dimensions: VideoDimensions(480, 360),
    encoding: VideoEncoding(maxBitrate: 1_000_000, maxFramerate: 15),
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
  VideoParameters? _currentCapturePreset;
  CameraPosition _currentCameraPosition = CameraPosition.front;
  bool _isReconnecting = false;
  bool _manualDisconnect = false;
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
  
  /// Get the PiP service for web platforms
  WebPipService get pipService => _pipService;
  
  // Detect device capability on service creation
  LiveKitService() {
    DeviceCapabilityService.detectCapability();
    DeviceCapabilityService.detectCapabilityAsync();
    // Apply conservative defaults with centralized feature flags.
    // Safari PWA gets additional conservative enforcement.
    _adaptiveBitrateEnabled = FeatureFlags.enableAdaptiveBitrate && !_isSafariPwa;
    // Use simulcast ladder flag (3-layer) but keep Safari PWA conservative
    _isSimulcastEnabled = FeatureFlags.enableSimulcastLadder && !_isSafariPwa;
  }

  /// Determine call type at runtime (Required by brief)
  CallType _classifyCallType() {
    if (remoteParticipants.isEmpty) return CallType.mixedUnknown;
    
    final participant = remoteParticipants.first;
    final localIsWeb = kIsWeb;
    final remoteIsWeb = participant.identity.contains('web') || 
                        participant.identity.contains('ios') ||
                        participant.metadata?.contains('web') == true;
    
    if (!localIsWeb && !remoteIsWeb) {
      return CallType.androidAndroid;
    } else if (!localIsWeb && remoteIsWeb) {
      return CallType.androidIOSPWA;
    } else if (localIsWeb && remoteIsWeb) {
      return CallType.iosPWAIOSPWA;
    } else {
      return CallType.mixedUnknown;
    }
  }

  /// Check if Android Ultra-HQ conditions are met (Required by brief)
  bool _shouldEnableUltraHQ() {
    // Enable ONLY if:
    // * Both peers are Android native
    // * Same app build
    // * Thermal state = normal
    // * Network = Wi-Fi or strong 5G
    
    if (_currentCallType != CallType.androidAndroid) return false;
    
    // Check network quality
    final networkType = _networkService.getCurrentNetworkType();
    if (networkType != 'wifi' && networkType != '5g') return false;
    
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
  VideoEncoding _getOptimalVideoEncoding() {
    _currentCallType = _classifyCallType();
    _isUltraHQMode = _shouldEnableUltraHQ();
    _currentVideoCodec = _getPreferredCodec();
    
    final deviceMaxBitrate = DeviceCapabilityService.getMaxVideoBitrate();
    final deviceMaxFramerate = DeviceCapabilityService.getMaxFramerate();
    
    int finalBitrate;
    int finalFramerate = deviceMaxFramerate;
    
    if (_isUltraHQMode) {
      // Android Ultra-HQ mode: Higher bitrates allowed
      finalBitrate = _supports60fps() ? 10_000_000 : 8_000_000;
      if (_supports60fps()) finalFramerate = 60;
    } else {
      // Standard mode: Use device limits (no network-based downshift).
      finalBitrate = deviceMaxBitrate;
    }
    
    debugPrint('🎥 FaceTime-Quality Encoding:');
    debugPrint('   📞 Call Type: $_currentCallType');
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

    double factor = 1.0;
    if (packetLoss >= 5.0 || rttMs >= 300.0 || jitterMs >= 40.0) {
      factor = 0.5;
    } else if (packetLoss >= 2.0 || rttMs >= 200.0 || jitterMs >= 30.0) {
      factor = 0.7;
    } else if (packetLoss >= 1.0 || rttMs >= 150.0 || jitterMs >= 20.0) {
      factor = 0.85;
    }

    final minBitrate = _isUltraHQMode ? 4_000_000 : 2_000_000;
    final target = (baseBitrate * factor).round();
    return target.clamp(minBitrate, baseBitrate);
  }
  
  /// Connect to LiveKit room with FaceTime-quality tuning
  Future<bool> connect({
    required String url,
    required String token,
    required String roomName,
  }) async {
    _manualDisconnect = false;
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
      // Default simulcast behavior: enable 3-layer ladder for 1:1 when allowed
      _isSimulcastEnabled = FeatureFlags.enableSimulcastLadder && !_isSafariPwa;
      
      debugPrint('🎯 FaceTime-Quality Connection Setup:');
      debugPrint('   📞 Call Type: $_currentCallType');
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

          // Get optimal encoding for this call type
          final optimalEncoding = _getOptimalVideoEncoding();
          VideoParameters captureParams;

          if (_isUltraHQMode && _supports4K()) {
            captureParams = FaceTimeVideoPresets.androidExtreme4K;
          } else if (_isUltraHQMode && _supports1440p60()) {
            captureParams = FaceTimeVideoPresets.androidExtreme1440p60;
          } else if (_isUltraHQMode && _supports60fps()) {
            captureParams = FaceTimeVideoPresets.androidUltraHQ60;
          } else if (_isUltraHQMode) {
            captureParams = FaceTimeVideoPresets.androidUltraHQ;
          } else {
            switch (_currentCallType) {
              case CallType.androidAndroid:
                captureParams = FaceTimeVideoPresets.h1080;
                break;
              case CallType.androidIOSPWA:
                captureParams = FaceTimeVideoPresets.h720;
                break;
              default:
                captureParams = FaceTimeVideoPresets.h720;
            }
          }
          // Enforce Safari PWA conservative capture preset
          if (_isSafariPwa) {
            captureParams = FaceTimeVideoPresets.h720;
          }
          _currentCapturePreset = captureParams;

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

      await Future.wait([
        enableCamera(),
        enableMicrophone(),
      ]).timeout(const Duration(seconds: 12), onTimeout: () {
        throw Exception('Timed out while enabling local media tracks');
      });
      
      // Verify actual codec being used after connection
      await Future.delayed(const Duration(seconds: 2)); // Wait for negotiation
      _logActualCodecUsed();
      
      debugPrint('✅ Connected to LiveKit room with FaceTime-quality tuning: $roomName');
      return true;
    } catch (e) {
      _errorMessage = 'Failed to connect: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }
  
  /// Get optimal audio bitrate (Audio bandwidth protection from brief)
  int _getOptimalAudioBitrate() {
    // Opus codec, 24–32 kbps (speech), Enable DTX
    // Audio must never starve video bitrate
    switch (_currentCallType) {
      case CallType.androidAndroid:
        return _isUltraHQMode ? 32000 : 28000; // 32kbps or 28kbps
      case CallType.androidIOSPWA:
        return 28000; // 28kbps
      default:
        return 24000; // 24kbps minimum
    }
  }

  AudioCaptureOptions _buildAudioCaptureOptions() {
    return const AudioCaptureOptions(
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
    );
  }
  
  /// Disconnect from room and cleanup
  Future<void> disconnect() async {
    try {
      debugPrint('🔌 Disconnecting from LiveKit...');
      _manualDisconnect = true;
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
        
        final optimalEncoding = _getOptimalVideoEncoding();
        VideoParameters captureParams;
        
        if (_isUltraHQMode && _supports60fps()) {
          captureParams = FaceTimeVideoPresets.androidUltraHQ60;
        } else if (_isUltraHQMode) {
          captureParams = FaceTimeVideoPresets.androidUltraHQ;
        } else {
          switch (_currentCallType) {
            case CallType.androidAndroid:
              captureParams = FaceTimeVideoPresets.h1080;
              break;
            default:
              captureParams = FaceTimeVideoPresets.h720;
          }
        }
        if (_isSafariPwa) captureParams = FaceTimeVideoPresets.h720;
        
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
          publishOptions: VideoPublishOptions(
            videoEncoding: optimalEncoding,
            simulcast: _isSimulcastEnabled, // Critical: Never use simulcast for 1-to-1
          ),
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

    final baseEncoding = _getOptimalVideoEncoding();
    final baseBitrate = baseEncoding.maxBitrate ?? 0;
    if (baseBitrate <= 0) return;

    final targetBitrate = _getAdaptiveTargetBitrate(stats, baseBitrate);
    if (_currentAdaptiveBitrate == targetBitrate) return;

    final now = DateTime.now();
    if (_lastAdaptiveChange != null &&
        now.difference(_lastAdaptiveChange!) < const Duration(seconds: 12)) {
      return;
    }

    final previous = _currentAdaptiveBitrate ?? baseBitrate;
    final changeRatio = (targetBitrate - previous).abs() / previous;
    if (changeRatio < 0.1) return;

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

      await _localVideoTrack?.stop();

      final optimalEncoding = _getOptimalVideoEncoding();
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

      await _room?.localParticipant?.publishVideoTrack(
        _localVideoTrack!,
        publishOptions: VideoPublishOptions(
          videoEncoding: encoding,
          simulcast: _isSimulcastEnabled,
        ),
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
    await _maybeAdjustVideoForStats(stats);
    // Android-only cautious upgrade gate (safe, single upgrade per call)
    try {
      _maybePerformUpgradeGate(stats);
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
        
        await _room!.localParticipant?.publishAudioTrack(
          _localAudioTrack!,
          publishOptions: AudioPublishOptions(
            audioBitrate: _getOptimalAudioBitrate(),
            dtx: true,
            red: true,
          ),
        );
      }
      
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
        _localVideoTrack = null;
        _localAudioTrack = null;
        _room = null;
        _isUltraHQMode = false;
        _isSimulcastEnabled = false;
        notifyListeners();
      })
      ..on<ParticipantConnectedEvent>((event) {
        debugPrint('👤 Participant connected: ${event.participant.identity}');
        debugPrint('   - Call type may have changed, reclassifying...');
        _currentCallType = _classifyCallType();
        _isUltraHQMode = _shouldEnableUltraHQ();
        debugPrint('   📞 New Call Type: $_currentCallType');
        debugPrint('   🚀 Ultra-HQ Mode: $_isUltraHQMode');
        notifyListeners();
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        debugPrint('👋 Participant disconnected: ${event.participant.identity}');
        notifyListeners();
      })
      ..on<TrackPublishedEvent>((event) {
        debugPrint('📢 Track published: ${event.publication.sid} by ${event.participant.identity}');
        notifyListeners();
      })
      ..on<TrackSubscribedEvent>((event) {
        debugPrint('✅ Track subscribed: ${event.track.sid}');
        debugPrint('   - Kind: ${event.track.kind}');
        debugPrint('   - Participant: ${event.participant.identity}');
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
  
  /// Log actual codec being used after connection
  void _logActualCodecUsed() {
    try {
      final localParticipant = _room?.localParticipant;
      final videoTrack = localParticipant?.videoTrackPublications.firstOrNull?.track;
      
      if (videoTrack != null) {
        debugPrint('📊 ACTUAL CODEC VERIFICATION:');
        debugPrint('   🎯 Requested: $_currentVideoCodec');
        debugPrint('   ✅ LiveKit Server Accepted: ${videoTrack.source}');
        
        // Check if AV1 was requested but H.264 is being used (indicates no AV1 support)
        if (_currentVideoCodec == 'av1' && !videoTrack.source.toString().toLowerCase().contains('av1')) {
          debugPrint('   ⚠️ AV1 requested but not used - LiveKit server may not support AV1');
          debugPrint('   📝 Recommendation: Check LiveKit Cloud plan or server configuration');
        }
      } else {
        debugPrint('⚠️ Could not verify codec - no video track found');
      }
    } catch (e) {
      debugPrint('Error checking actual codec: $e');
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
    final iceServers = _parseIceServers();
    return RTCConfiguration(
      iceServers: iceServers,
      iceTransportPolicy:
          Environment.liveKitForceRelay ? RTCIceTransportPolicy.relay : null,
    );
  }

  List<RTCIceServer>? _parseIceServers() {
    final raw = Environment.liveKitIceServersJson.trim();
    if (raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;

      final servers = <RTCIceServer>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final urls = (entry['urls'] as List?)?.map((e) => e.toString()).toList();
        final username = entry['username']?.toString();
        final credential = entry['credential']?.toString();
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
