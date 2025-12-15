import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'network_quality_service.dart';
import 'device_capability_service.dart';
import 'call_stats_service.dart';
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
    encoding: VideoEncoding(maxBitrate: 6_000_000, maxFramerate: 30),
  );

  // Cross-Platform 720p Fallback
  static final h720 = VideoParameters(
    dimensions: VideoDimensions(1280, 720),
    encoding: VideoEncoding(maxBitrate: 3_500_000, maxFramerate: 30),
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
  String _currentVideoCodec = 'h264';
  CameraPosition _currentCameraPosition = CameraPosition.front;
  
  Room? get room => _room;
  LocalVideoTrack? get localVideoTrack => _localVideoTrack;
  LocalAudioTrack? get localAudioTrack => _localAudioTrack;
  CallType get currentCallType => _currentCallType;
  bool get isUltraHQMode => _isUltraHQMode;
  bool get isSimulcastEnabled => _isSimulcastEnabled;
  String get currentVideoCodec => _currentVideoCodec;
  
  bool get isConnected => _room?.connectionState == ConnectionState.connected;
  bool get isMicrophoneEnabled => _localAudioTrack?.muted == false;
  bool get isCameraEnabled => _localVideoTrack?.muted == false;
  
  List<Participant> get remoteParticipants => 
      _room?.remoteParticipants.values.toList() ?? [];
  
  LocalParticipant? get localParticipant => _room?.localParticipant;
  
  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  
  final NetworkQualityService _networkService = NetworkQualityService();
  CallStatsService? _internalStatsService;
  final WebPipService _pipService = WebPipService();
  
  /// Get the PiP service for web platforms
  WebPipService get pipService => _pipService;
  
  // Detect device capability on service creation
  LiveKitService() {
    DeviceCapabilityService.detectCapability();
    DeviceCapabilityService.detectCapabilityAsync();
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
    
    return true;
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
    
    // Get device capability limits
    final deviceCapability = DeviceCapabilityService.capability;
    final deviceMaxBitrate = DeviceCapabilityService.getMaxVideoBitrate();
    final deviceMaxFramerate = DeviceCapabilityService.getMaxFramerate();
    
    // Get network recommendation
    final networkBitrate = _networkService.getRecommendedVideoBitrate();
    
    int finalBitrate;
    int finalFramerate = deviceMaxFramerate;
    
    // Special handling for low-end devices
    if (deviceCapability == DeviceCapability.lowEnd) {
      finalBitrate = deviceMaxBitrate; // Use conservative 2 Mbps
      finalFramerate = 15; // Lower framerate for stability
      debugPrint('🔧 Low-end device optimization applied');
      return VideoEncoding(
        maxBitrate: finalBitrate,
        maxFramerate: finalFramerate,
      );
    }
    
    if (_isUltraHQMode) {
      // Android Ultra-HQ mode: Higher bitrates allowed
      finalBitrate = _supports60fps() ? 10_000_000 : 8_000_000;
      if (_supports60fps()) finalFramerate = 60;
    } else {
      // Standard mode: Conservative defaults
      finalBitrate = deviceMaxBitrate < networkBitrate ? deviceMaxBitrate : networkBitrate;
      
      // Apply FaceTime-quality minimums
      switch (_currentCallType) {
        case CallType.androidAndroid:
          finalBitrate = finalBitrate < 6_000_000 ? 6_000_000 : finalBitrate;
          break;
        case CallType.androidIOSPWA:
          finalBitrate = finalBitrate < 4_000_000 ? 4_000_000 : finalBitrate;
          break;
        default:
          finalBitrate = finalBitrate < 3_000_000 ? 3_000_000 : finalBitrate;
      }
    }
    
    debugPrint('🎥 FaceTime-Quality Encoding:');
    debugPrint('   📞 Call Type: $_currentCallType');
    debugPrint('   🚀 Ultra-HQ Mode: $_isUltraHQMode');
    debugPrint('   📡 Codec: $_currentVideoCodec');
    debugPrint('   📊 Bitrate: ${finalBitrate / 1000000} Mbps');
    debugPrint('   🎬 FPS: $finalFramerate');
    
    return VideoEncoding(
      maxBitrate: finalBitrate,
      maxFramerate: finalFramerate,
    );
  }
  
  /// Connect to LiveKit room with FaceTime-quality tuning
  Future<bool> connect({
    required String url,
    required String token,
    required String roomName,
  }) async {
    try {
      _errorMessage = null;
      
      _currentCallType = _classifyCallType();
      _isUltraHQMode = _shouldEnableUltraHQ();
      _currentVideoCodec = _getPreferredCodec();
      _isSimulcastEnabled = false; // Always false for 1-to-1 calls (brief requirement)
      
      debugPrint('🎯 FaceTime-Quality Connection Setup:');
      debugPrint('   📞 Call Type: $_currentCallType');
      debugPrint('   🚀 Ultra-HQ Mode: $_isUltraHQMode');
      debugPrint('   📡 Preferred Codec: $_currentVideoCodec');
      debugPrint('   🔄 Simulcast: $_isSimulcastEnabled (disabled for 1-to-1)');
      
      _room = Room();
      _setupRoomListeners();
      _networkService.startMonitoring();
      
      // Get optimal encoding for this call type
      final optimalEncoding = _getOptimalVideoEncoding();
      VideoParameters captureParams;
      
      // Select capture parameters based on device capability first
      final deviceCapability = DeviceCapabilityService.capability;
      
      if (deviceCapability == DeviceCapability.lowEnd) {
        // Low-end devices: Use 480p for stability
        captureParams = FaceTimeVideoPresets.lowEnd480p;
      } else if (_isUltraHQMode && _supports4K()) {
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
      
      await _room!.connect(
        url,
        token,
        connectOptions: ConnectOptions(
          autoSubscribe: true,
        ),
        roomOptions: RoomOptions(
          defaultCameraCaptureOptions: CameraCaptureOptions(
            maxFrameRate: (optimalEncoding.maxFramerate ?? 30).toDouble(),
            params: captureParams,
          ),
          defaultScreenShareCaptureOptions: ScreenShareCaptureOptions(
            maxFrameRate: 15,
            params: FaceTimeVideoPresets.h720,
          ),
          defaultAudioCaptureOptions: AudioCaptureOptions(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          ),
          defaultVideoPublishOptions: VideoPublishOptions(
            videoEncoding: optimalEncoding,
            simulcast: _isSimulcastEnabled, // Critical: Never use simulcast for 1-to-1
            // No simulcast layers when simulcast is disabled
          ),
          defaultAudioPublishOptions: AudioPublishOptions(
            audioBitrate: _getOptimalAudioBitrate(),
          ),
          adaptiveStream: true,
          dynacast: true,
        ),
      );

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
  
  /// Disconnect from room and cleanup
  Future<void> disconnect() async {
    try {
      debugPrint('🔌 Disconnecting from LiveKit...');
      
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
        
        // Select capture parameters based on device capability
        final deviceCapability = DeviceCapabilityService.capability;
        
        if (deviceCapability == DeviceCapability.lowEnd) {
          // Low-end devices: Use 480p for stability
          captureParams = FaceTimeVideoPresets.lowEnd480p;
        } else if (_isUltraHQMode && _supports60fps()) {
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
        
        debugPrint('📹 FaceTime-quality capture params:');
        debugPrint('   📐 Resolution: ${captureParams.dimensions.width}x${captureParams.dimensions.height}');
        final encoding = captureParams.encoding;
        final bitrate = encoding?.maxBitrate ?? 6000000;
        final framerate = encoding?.maxFramerate ?? 30;
        debugPrint('   📊 Max Bitrate: ${bitrate / 1000000} Mbps');
        debugPrint('   🎬 Max FPS: $framerate');
        
        _localVideoTrack = await LocalVideoTrack.createCameraTrack(
          CameraCaptureOptions(
            maxFrameRate: (optimalEncoding.maxFramerate ?? 30).toDouble(),
            params: captureParams,
          ),
        );
        
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
      _errorMessage = 'Failed to enable camera: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Apply bitrate & adaptation policy (From brief)
  Future<void> _maybeAdjustVideoForStats(CallStats stats) async {
    try {
      if (_room == null) return;
      
      final int bitrate = stats.videoSendBitrate.toInt();
      final double packetLossPct = stats.videoPacketLoss;
      final double rttMs = stats.roundTripTime * 1000.0;
      final double jitterMs = stats.jitter * 1000.0;

      // Bitrate & Adaptation Policy from brief:
      // * Allow bitrate bursting
      // * Prefer dropping FPS before resolution
      // * Avoid dropping below 720p unless packet loss > ~5%
      
      VideoParameters desiredPreset;
      int? maxBitrateOverride;
      
      if (packetLossPct > 5.0) {
        // Poor conditions: drop to 720p but maintain bitrate
        desiredPreset = FaceTimeVideoPresets.h720;
        maxBitrateOverride = (_isUltraHQMode ? 5_000_000 : 3_500_000);
      } else if (rttMs > 300.0 || jitterMs > 50.0) {
        // Network issues: reduce FPS before resolution
        desiredPreset = _isUltraHQMode ? FaceTimeVideoPresets.androidUltraHQ : FaceTimeVideoPresets.h1080;
        maxBitrateOverride = (_isUltraHQMode ? 6_000_000 : 4_000_000);
      } else {
        // Good conditions: use optimal settings
        if (_isUltraHQMode && _supports60fps()) {
          desiredPreset = FaceTimeVideoPresets.androidUltraHQ60;
        } else if (_isUltraHQMode) {
          desiredPreset = FaceTimeVideoPresets.androidUltraHQ;
        } else {
          desiredPreset = FaceTimeVideoPresets.h1080;
        }
      }

      debugPrint('🔧 FaceTime-Quality Adjustment:');
      debugPrint('   📊 Bitrate: $bitrate bps');
      debugPrint('   📉 Packet Loss: ${packetLossPct.toStringAsFixed(1)}%');
      debugPrint('   ⏱️ RTT: ${rttMs.toStringAsFixed(0)}ms');
      debugPrint('   📶 Jitter: ${jitterMs.toStringAsFixed(0)}ms');
      debugPrint('   🎯 Target Preset: ${desiredPreset.dimensions.width}x${desiredPreset.dimensions.height}');
      
      await _recreateAndPublishVideoTrack(desiredPreset, maxBitrateOverride: maxBitrateOverride);
    } catch (e) {
      debugPrint('Error adjusting video for stats: $e');
    }
  }

  /// Recreate and publish local camera track
  Future<void> _recreateAndPublishVideoTrack(
    VideoParameters preset, {
    int? maxBitrateOverride,
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
        ),
      );

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
    } catch (e) {
      debugPrint('Failed to recreate video track: $e');
    }
  }

  /// External entrypoint: apply observed stats
  Future<void> applyObservedStats(CallStats stats) async {
    await _maybeAdjustVideoForStats(stats);
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
          AudioCaptureOptions(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
            // DTX enabled by default in LiveKit for better bandwidth efficiency
          ),
        );
        
        await _room!.localParticipant?.publishAudioTrack(_localAudioTrack!);
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
      ..on<RoomDisconnectedEvent>((event) {
        debugPrint('🔌 Room disconnected: ${event.reason}');
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
    _pipService.setupAutoEnterPip();
  }
  
  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
