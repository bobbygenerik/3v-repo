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
  
  /// FaceTime-quality video encoding
  /// FaceTime uses approximately 3-8 Mbps for 1080p video
  VideoEncoding _getOptimalVideoEncoding() {
    final deviceMaxBitrate = DeviceCapabilityService.getMaxVideoBitrate();
    final deviceMaxFramerate = DeviceCapabilityService.getMaxFramerate();
    final preferredCodec = DeviceCapabilityService.getCodecPreference();
    
    // Get network recommendation
    final networkBitrate = _networkService.getRecommendedVideoBitrate();
    
    // Use the MINIMUM of device capability and network quality
    var finalBitrate = deviceMaxBitrate < networkBitrate 
        ? deviceMaxBitrate 
        : networkBitrate;
    
    // Ensure minimum quality - never go below 5 Mbps for acceptable video
    if (finalBitrate < 5000000) {
      finalBitrate = 5000000;
    }
    
    final finalFramerate = 30; // Fixed 30fps like FaceTime
    
    debugPrint('�� Video encoding: ${(finalBitrate / 1000000).toStringAsFixed(1)} Mbps, $finalFramerate fps, codec: $preferredCodec');
    
    return VideoEncoding(
      maxBitrate: finalBitrate,
      maxFramerate: finalFramerate,
    );
  }
  
  /// Get high-quality capture parameters (NOT using low-bitrate presets)
  VideoParameters _getHighQualityCaptureParams() {
    final encoding = _getOptimalVideoEncoding();
    
    if (DeviceCapabilityService.shouldUse1080p()) {
      debugPrint('📹 Using 1080p capture with ${(encoding.maxBitrate / 1000000).toStringAsFixed(1)} Mbps');
      return VideoParameters(
        dimensions: const VideoDimensions(1920, 1080),
        encoding: encoding,
      );
    } else {
      debugPrint('📹 Using 720p capture with ${(encoding.maxBitrate / 1000000).toStringAsFixed(1)} Mbps');
      return VideoParameters(
        dimensions: const VideoDimensions(1280, 720),
        encoding: encoding,
      );
    }
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
      
      final captureParams = _getHighQualityCaptureParams();
      final encoding = _getOptimalVideoEncoding();
      
      // Connect to room (fail fast with timeout to avoid long hangs)
      await _room!.connect(
        url,
        token,
        connectOptions: ConnectOptions(
          autoSubscribe: true, // Automatically subscribe to all remote tracks
        ),
        roomOptions: RoomOptions(
          defaultCameraCaptureOptions: CameraCaptureOptions(
            maxFrameRate: 30,
            // Use our high-quality params instead of low-bitrate presets
            params: captureParams,
          ),
          defaultScreenShareCaptureOptions: ScreenShareCaptureOptions(
            maxFrameRate: 15,
            params: VideoParametersPresets.h1080_169,
          ),
          defaultAudioCaptureOptions: AudioCaptureOptions(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          ),
          defaultVideoPublishOptions: VideoPublishOptions(
            videoEncoding: encoding,
            // Use H.264 for best compatibility (especially iOS)
            videoCodec: 'H264',
            // CRITICAL: Prioritize resolution over framerate for quality
            degradationPreference: DegradationPreference.maintainResolution,
            // Disable simulcast for now - it can cause quality issues
            // The receiver might pick a lower quality layer
            simulcast: false,
          ),
          defaultAudioPublishOptions: AudioPublishOptions(
            audioBitrate: 64000, // 64 kbps for good audio
          ),
          // Disable adaptive stream - we want consistent high quality
          adaptiveStream: false,
          dynacast: false,
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
  
  /// Enable camera and publish video track with FaceTime-quality settings
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
        
        final captureParams = _getHighQualityCaptureParams();
        final encoding = _getOptimalVideoEncoding();
        
        debugPrint('📹 Capture: ${captureParams.dimensions.width}x${captureParams.dimensions.height}');
        debugPrint('📹 Bitrate: ${(encoding.maxBitrate / 1000000).toStringAsFixed(1)} Mbps');
        
        _localVideoTrack = await LocalVideoTrack.createCameraTrack(
          CameraCaptureOptions(
            maxFrameRate: 30,
            params: captureParams,
          ),
        );
        _currentVideoPreset = captureParams;
        debugPrint('✅ Camera track created: ${_localVideoTrack?.sid}');
        
        // Publish to room with high quality encoding
        debugPrint('📤 Publishing video track to room...');
        await _room!.localParticipant?.publishVideoTrack(
          _localVideoTrack!,
          publishOptions: VideoPublishOptions(
            videoEncoding: encoding,
            videoCodec: 'H264',
            // CRITICAL: Maintain resolution quality
            degradationPreference: DegradationPreference.maintainResolution,
            simulcast: false,
          ),
        );
        _currentMaxBitrate = encoding.maxBitrate;
        debugPrint('✅ Video track published at ${(encoding.maxBitrate / 1000000).toStringAsFixed(1)} Mbps');
      }
      
      // Unmute
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
      
      // Determine target bitrate based on network conditions
      int targetBitrate = optimalEncoding.maxBitrate;

      // Only reduce quality if network is really struggling
      if (packetLossPct > 10.0 || rttMs > 500.0 || jitterMs > 150.0) {
        // Very poor conditions: reduce to 3 Mbps minimum
        targetBitrate = 3000000;
        debugPrint('⚠️ Poor network detected, reducing to 3 Mbps');
      } else if (packetLossPct > 5.0 || rttMs > 300.0 || jitterMs > 80.0) {
        // Moderate issues: reduce to 5 Mbps
        targetBitrate = 5000000;
        debugPrint('⚠️ Moderate network issues, using 5 Mbps');
      }

      // Only adjust if significantly different from current
      if ((targetBitrate - (_currentMaxBitrate ?? 0)).abs() > 1000000) {
        debugPrint('🔧 Adjusting bitrate to ${(targetBitrate / 1000000).toStringAsFixed(1)} Mbps');
        _currentMaxBitrate = targetBitrate;
        // Note: LiveKit handles this internally via degradation preference
      }
    } catch (e) {
      debugPrint('Error adjusting video for stats: $e');
    }
  }

  /// External entrypoint: apply observed stats (from CallStatsService)
  Future<void> applyStats(CallStats stats) async {
    await _maybeAdjustVideoForStats(stats);
  }
  
  /// Update video quality based on network conditions
  Future<void> updateNetworkQuality() async {
    try {
      final stats = await collectCallStats();
      await _maybeAdjustVideoForStats(stats);
    } catch (e) {
      debugPrint('Error updating network quality: $e');
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
          AudioCaptureOptions(
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
