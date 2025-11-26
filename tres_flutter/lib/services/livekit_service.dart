import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'network_quality_service.dart';
import 'device_capability_service.dart';
import 'call_stats_service.dart';
import 'web_pip_helper.dart';
import 'web_pip_bridge_stub.dart'
    if (dart.library.html) 'web_pip_bridge.dart';
// `CallStats` and `CallConnectionQuality` are exported via `call_stats_service.dart`

/// LiveKit service managing room connections and participant tracks
/// Mirrors functionality from Android LiveKitManager.kt
enum CaptureProfile { low, medium, high }

class LiveKitService extends ChangeNotifier {
  Room? _room;
  LocalVideoTrack? _localVideoTrack;
  LocalAudioTrack? _localAudioTrack;
  dynamic _currentVideoPreset;
  int? _currentMaxBitrate;
  CameraPosition _currentCameraPosition = CameraPosition.front; // Track current camera
  
  Room? get room => _room;
  LocalVideoTrack? get localVideoTrack => _localVideoTrack;
  LocalAudioTrack? get localAudioTrack => _localAudioTrack;
  
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
    // Perform async detection to get a more accurate capability and codec preference
    DeviceCapabilityService.detectCapability();
    // Also attempt async detection (non-blocking) for finer-grained heuristics
    DeviceCapabilityService.detectCapabilityAsync();
  }

  /// Collect call stats from local tracks using LiveKit SDK where available.
  /// Returns a [CallStats] instance. This method does not fall back to
  /// simulated data — if stats are unavailable the returned [CallStats]
  /// will contain zero/unknown values and `quality` set to `unknown`.
  Future<CallStats> collectCallStats() async {
    try {
      // Prefer real stats from the CallStatsService which listens to LiveKit events.
      if (_room == null) return const CallStats();

      _internalStatsService ??= CallStatsService();
      try {
        await _internalStatsService!.initialize(_room!);
      } catch (_) {}
      if (!_internalStatsService!.isCollecting) {
        _internalStatsService!.startCollecting();
      }

      // Return the latest collected stats (may be empty if called immediately)
      return _internalStatsService!.currentStats;
    } catch (e) {
      debugPrint('collectCallStats fatal: $e');
      return const CallStats();
    }
  }
  
  /// Get optimal video encoding with enhanced codec optimization
  VideoEncoding _getOptimalVideoEncoding() {
    // Get device capability limits (now with increased bitrates)
    final deviceMaxBitrate = DeviceCapabilityService.getMaxVideoBitrate();
    final deviceMaxFramerate = DeviceCapabilityService.getMaxFramerate();
    final preferredCodec = DeviceCapabilityService.getCodecPreference();
    
    // Get network recommendation
    final networkBitrate = _networkService.getRecommendedVideoBitrate();
    
    // Use the MINIMUM of device capability and network quality
    final finalBitrate = deviceMaxBitrate < networkBitrate 
        ? deviceMaxBitrate 
        : networkBitrate;
    
    final finalFramerate = networkBitrate < 600000 
        ? (deviceMaxFramerate * 0.8).toInt()
        : deviceMaxFramerate;
    
    debugPrint('🎥 Video encoding: $finalBitrate bps, $finalFramerate fps, codec: $preferredCodec');
    
    if (kIsWeb) {
      // Web: Force H.264 for maximum iOS/Safari compatibility
      // VP9 is not well supported on iPhone browsers
      // Use higher bitrate on web to ensure good quality from browsers
      final webBitrate = finalBitrate < 8000000 ? 8000000 : finalBitrate;
      debugPrint('🌐 Web platform: Using H.264 codec with enhanced bitrate: ${(webBitrate / 1000000).toStringAsFixed(1)} Mbps');
      return VideoEncoding(
        maxBitrate: webBitrate, // Ensure minimum 8 Mbps for web senders
        maxFramerate: finalFramerate,
      );
    }
    
    return VideoEncoding(
      maxBitrate: finalBitrate,
      maxFramerate: finalFramerate,
    );
  }
  
  /// Connect to LiveKit room
  /// Returns true if connection successful
  Future<bool> connect({
    required String url,
    required String token,
    required String roomName,
  }) async {
    try {
      _errorMessage = null;
      
      // Create room instance
      _room = Room();
      
      // Set up event listeners before connecting
      _setupRoomListeners();
      
      // Start network monitoring
      _networkService.startMonitoring();
      
      // Connect to room (fail fast with timeout to avoid long hangs)
      await _room!.connect(
        url,
        token,
        connectOptions: ConnectOptions(
          autoSubscribe: true, // Automatically subscribe to all remote tracks
        ),
        roomOptions: RoomOptions(
          defaultCameraCaptureOptions: CameraCaptureOptions(
            maxFrameRate: DeviceCapabilityService.getMaxFramerate().toDouble(),
            // Use 1080p for high-end devices (including web), 720p otherwise
            params: DeviceCapabilityService.shouldUse1080p() 
                ? VideoParametersPresets.h1080_169 
                : VideoParametersPresets.h720_169,
          ),
          defaultScreenShareCaptureOptions: ScreenShareCaptureOptions(
            maxFrameRate: 15,
            params: VideoParametersPresets.h720_169,
          ),
          defaultAudioCaptureOptions: AudioCaptureOptions(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          ),
          defaultVideoPublishOptions: VideoPublishOptions(
            videoEncoding: _getOptimalVideoEncoding(),
            // Enable simulcast with multiple quality layers for better adaptation
            simulcast: true,
            // Provide multiple quality layers so receivers can choose best quality
            // Top layer matches capture resolution (1080p for high-end, 720p otherwise)
            videoSimulcastLayers: DeviceCapabilityService.shouldUse1080p()
                ? [
                    // High-end: 1080p, 720p, 360p layers
                    VideoParameters(
                      dimensions: VideoDimensions(1920, 1080),
                      encoding: VideoEncoding(maxBitrate: 8000000, maxFramerate: 60),
                    ),
                    VideoParameters(
                      dimensions: VideoDimensions(1280, 720),
                      encoding: VideoEncoding(maxBitrate: 4000000, maxFramerate: 30),
                    ),
                    VideoParameters(
                      dimensions: VideoDimensions(640, 360),
                      encoding: VideoEncoding(maxBitrate: 1500000, maxFramerate: 30),
                    ),
                  ]
                : [
                    // Mid/Low-end: 720p, 480p, 240p layers
                    VideoParameters(
                      dimensions: VideoDimensions(1280, 720),
                      encoding: VideoEncoding(maxBitrate: 4000000, maxFramerate: 30),
                    ),
                    VideoParameters(
                      dimensions: VideoDimensions(640, 480),
                      encoding: VideoEncoding(maxBitrate: 1500000, maxFramerate: 30),
                    ),
                    VideoParameters(
                      dimensions: VideoDimensions(320, 240),
                      encoding: VideoEncoding(maxBitrate: 500000, maxFramerate: 24),
                    ),
                  ],
          ),
          defaultAudioPublishOptions: AudioPublishOptions(
            audioBitrate: _networkService.getRecommendedAudioBitrate(),
          ),
          // Enable adaptive streaming with higher baseline quality
          adaptiveStream: true,
          dynacast: true,
        ),
      );

      // Enable local tracks with timeout
      await Future.wait([
        enableCamera(),
        enableMicrophone(),
      ]).timeout(const Duration(seconds: 12), onTimeout: () {
        throw Exception('Timed out while enabling local media tracks');
      });
      
      debugPrint('✅ Connected to LiveKit room: $roomName');
      return true;
    } catch (e) {
      _errorMessage = 'Failed to connect: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }
  
  /// Disconnect from room and cleanup
  Future<void> disconnect() async {
    try {
      _networkService.stopMonitoring();
      _pipService.dispose();
      
      await _localVideoTrack?.stop();
      await _localAudioTrack?.stop();
      
      await _room?.disconnect();
      
      _localVideoTrack = null;
      _localAudioTrack = null;
      _room = null;
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
  }
  
  /// Enable camera and publish video track
  Future<void> enableCamera() async {
    try {
      debugPrint('📹 enableCamera() called');
      if (_room == null) {
        debugPrint('❌ Room is null, cannot enable camera');
        return;
      }
      
      // Create camera track if not exists
      if (_localVideoTrack == null) {
        debugPrint('📹 Creating new camera track...');
        _localVideoTrack = await LocalVideoTrack.createCameraTrack(
          CameraCaptureOptions(
            maxFrameRate: DeviceCapabilityService.getMaxFramerate().toDouble(),
            // Force minimum 720p
            params: VideoParametersPresets.h720_169,
          ),
        );
        _currentVideoPreset = VideoParametersPresets.h720_169;
        debugPrint('✅ Camera track created: ${_localVideoTrack?.sid}');
        
        // Publish to room
        debugPrint('📤 Publishing video track to room...');
        await _room!.localParticipant?.publishVideoTrack(_localVideoTrack!);
        debugPrint('✅ Video track published');
      }
      
      // Unmute
      debugPrint('🎥 Unmuting video track...');
      await _localVideoTrack?.unmute();
      debugPrint('✅ Video track unmuted');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to enable camera: $e');
      _errorMessage = 'Failed to enable camera: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Adjust published video quality based on observed network/device stats.
  /// Adjusts both bitrate and FPS based on network conditions.
  Future<void> _maybeAdjustVideoForStats(CallStats stats) async {
    try {
      if (_room == null) return;
      
      final int bitrate = stats.videoSendBitrate.toInt();
      final double packetLossPct = stats.videoPacketLoss; // percent
      final double rttMs = stats.roundTripTime * 1000.0; // convert seconds->ms
      final double jitterMs = stats.jitter * 1000.0;

      // Get current optimal encoding based on network quality
      final optimalEncoding = _getOptimalVideoEncoding();
      
      // Always use 720p minimum resolution
      dynamic desired = VideoParametersPresets.h720_169;
      double? maxFpsOverride;
      int? maxBitrateOverride;

      // Determine target bitrate and FPS based on network conditions
      // Increased thresholds for better quality baseline
      if (packetLossPct > 8.0 || rttMs > 400.0 || jitterMs > 100.0 || bitrate < 300000) {
        // Very poor conditions: reduce FPS but maintain decent bitrate
        maxFpsOverride = 15.0;
        maxBitrateOverride = 5000 * 1000; // 5 Mbps minimum
      } else if (packetLossPct > 5.0 || rttMs > 250.0 || jitterMs > 60.0 || bitrate < 800000) {
        // Poor conditions: reduce FPS slightly, maintain good bitrate
        maxFpsOverride = 24.0;
        maxBitrateOverride = 8000 * 1000; // 8 Mbps
      } else if (bitrate <= 2000000) {
        // Medium conditions: maintain FPS, use high bitrate
        maxFpsOverride = DeviceCapabilityService.getMaxFramerate() * 0.9;
        maxBitrateOverride = 12000 * 1000; // 12 Mbps for better quality
      } else {
        // Good conditions: use optimal encoding from network quality
        maxFpsOverride = null;
        maxBitrateOverride = optimalEncoding.maxBitrate;
      }

      // Check if we need to adjust encoding
      final bool needsAdjustment = maxFpsOverride != null || 
                                   (maxBitrateOverride != _currentMaxBitrate);
      
      if (needsAdjustment) {
        final codec = DeviceCapabilityService.getCodecPreference();
      debugPrint('🔧 Video Quality Adjustment:');
      debugPrint('   📊 Bitrate: ${maxBitrateOverride ?? optimalEncoding.maxBitrate} bps (${((maxBitrateOverride ?? optimalEncoding.maxBitrate) / 1000000).toStringAsFixed(1)} Mbps)');
      debugPrint('   🎬 FPS: ${maxFpsOverride ?? DeviceCapabilityService.getMaxFramerate()}');
      debugPrint('   📡 Codec: $codec');
      debugPrint('   📉 Packet Loss: ${packetLossPct.toStringAsFixed(1)}%');
      debugPrint('   ⏱️ RTT: ${rttMs.toStringAsFixed(0)}ms');
      debugPrint('   📶 Jitter: ${jitterMs.toStringAsFixed(0)}ms');
        await _recreateAndPublishVideoTrack(
          desired, 
          maxFrameRateOverride: maxFpsOverride,
          maxBitrateOverride: maxBitrateOverride,
        );
      }
    } catch (e) {
      debugPrint('Error adjusting video for stats: $e');
    }
  }

  /// Recreate and publish local camera track for a requested preset.
  /// Optionally pass `maxFrameRateOverride` to cap capture FPS and
  /// `maxBitrateOverride` to set encoding bitrate.
  Future<void> _recreateAndPublishVideoTrack(
    dynamic preset, {
    double? maxFrameRateOverride,
    int? maxBitrateOverride,
  }) async {
    try {
      final wasMuted = !isCameraEnabled;

      // Stop old track if exists
      await _localVideoTrack?.stop();

      // Create new track with requested preset
      _localVideoTrack = await LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(
          maxFrameRate: (maxFrameRateOverride ?? DeviceCapabilityService.getMaxFramerate()).toDouble(),
          params: preset,
        ),
      );
      _currentVideoPreset = preset;

      // Publish new track with updated encoding if bitrate override provided
      if (maxBitrateOverride != null) {
        await _room?.localParticipant?.publishVideoTrack(
          _localVideoTrack!,
          publishOptions: VideoPublishOptions(
            videoEncoding: VideoEncoding(
              maxBitrate: maxBitrateOverride,
              maxFramerate: (maxFrameRateOverride ?? DeviceCapabilityService.getMaxFramerate()).toInt(),
            ),
          ),
        );
        _currentMaxBitrate = maxBitrateOverride;
      } else {
        await _room?.localParticipant?.publishVideoTrack(_localVideoTrack!);
      }

      // Restore mute state
      if (wasMuted) {
        await _localVideoTrack?.mute();
      } else {
        await _localVideoTrack?.unmute();
      }
      debugPrint('🔁 Recreated and published new video track with preset $preset');
    } catch (e) {
      debugPrint('Failed to recreate video track: $e');
    }
  }

  /// External entrypoint: apply observed stats (from CallStatsService)
  /// so LiveKitService can decide to adapt publish settings.
  Future<void> applyObservedStats(CallStats stats) async {
    await _maybeAdjustVideoForStats(stats);
  }

  /// Apply a high-level capture profile (low/medium/high) immediately.
  /// This is used by `PerformanceMonitor` to quickly lower capture
  /// resolution/fps when device or network conditions demand it.
  Future<void> applyCaptureProfile(CaptureProfile profile) async {
    try {
      if (_room == null) return;

      dynamic preset = VideoParametersPresets.h720_169;
      double? fpsOverride;

      switch (profile) {
        case CaptureProfile.low:
          preset = VideoParametersPresets.h360_169;
          fpsOverride = 15.0;
          break;
        case CaptureProfile.medium:
          preset = VideoParametersPresets.h720_169;
          fpsOverride = DeviceCapabilityService.getMaxFramerate() * 0.8;
          break;
        case CaptureProfile.high:
          preset = DeviceCapabilityService.shouldUse1080p()
              ? VideoParametersPresets.h1080_169
              : VideoParametersPresets.h720_169;
          fpsOverride = null; // don't force fps change for high
          break;
      }

      // Respect device capability
      if (!DeviceCapabilityService.shouldUse1080p() && preset == VideoParametersPresets.h1080_169) {
        preset = VideoParametersPresets.h720_169;
      }

      await _recreateAndPublishVideoTrack(preset, maxFrameRateOverride: fpsOverride);
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
  
  /// Enable microphone and publish audio track
  Future<void> enableMicrophone() async {
    try {
      if (_room == null) return;
      
      // Create audio track if not exists
      if (_localAudioTrack == null) {
        _localAudioTrack = await LocalAudioTrack.create(
          const AudioCaptureOptions(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          ),
        );
        
        // Publish to room
        await _room!.localParticipant?.publishAudioTrack(_localAudioTrack!);
      }
      
      // Unmute
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
  
  /// Switch between front and back camera
  Future<void> switchCamera() async {
    try {
      final track = _localVideoTrack;
      if (track == null) {
        debugPrint('❌ Cannot switch camera: no active video track');
        return;
      }
      
      // Toggle between front and back camera
      _currentCameraPosition = (_currentCameraPosition == CameraPosition.front)
          ? CameraPosition.back
          : CameraPosition.front;
      
      await track.setCameraPosition(_currentCameraPosition);
      debugPrint('✅ Camera switched to: $_currentCameraPosition');
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
    
    // Listen to room events
    _room!.createListener()
      ..on<RoomDisconnectedEvent>((event) {
        debugPrint('Room disconnected: ${event.reason}');
        notifyListeners();
      })
      ..on<ParticipantConnectedEvent>((event) {
        debugPrint('👤 Participant connected: ${event.participant.identity}');
        debugPrint('   - Video tracks: ${event.participant.videoTrackPublications.length}');
        debugPrint('   - Audio tracks: ${event.participant.audioTrackPublications.length}');
        notifyListeners();
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        debugPrint('👋 Participant disconnected: ${event.participant.identity}');
        notifyListeners();
      })
      ..on<TrackPublishedEvent>((event) {
        debugPrint('📢 Track published: ${event.publication.sid} by ${event.participant.identity}');
        debugPrint('   - Kind: ${event.publication.kind}');
        debugPrint('   - Source: ${event.publication.source}');
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
  
  /// Update the PiP video stream with the specified participant's video track
  /// This should be called when the main participant changes on web
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
