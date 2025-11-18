import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' show VideoParametersPresets;
import 'package:livekit_client/livekit_client.dart';
import 'network_quality_service.dart';
import 'device_capability_service.dart';

/// Capture profile enum for runtime adaptation
enum CaptureProfile { high, medium, low }

/// LiveKit service managing room connections and participant tracks
/// Mirrors functionality from Android LiveKitManager.kt
class LiveKitService extends ChangeNotifier {
  Room? _room;
  LocalVideoTrack? _localVideoTrack;
  LocalAudioTrack? _localAudioTrack;
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

  // Expose network service for external monitors
  NetworkQualityService get networkService => _networkService;
  
  // Detect device capability on service creation
  LiveKitService() {
    // Start async detection (non-blocking) to refine capability
    DeviceCapabilityService.detectCapability();
    DeviceCapabilityService.detectCapabilityAsync();
  }

  /// Capture profiles for adaptive switching
  /// High: high resolution/framerate/bitrate
  /// Medium: balanced
  /// Low: lowest for stability
  ///
  /// Note: applyCaptureProfile will re-create local camera track when possible.
  Future<void> applyCaptureProfile(CaptureProfile profile) async {
    try {
      if (_room == null) return;

      CameraCaptureOptions options;
      switch (profile) {
        case CaptureProfile.high:
          options = CameraCaptureOptions(
            maxFrameRate: DeviceCapabilityService.getMaxFramerate().toDouble(),
            params: DeviceCapabilityService.shouldUse1080p()
                ? VideoParametersPresets.h1080_169
                : VideoParametersPresets.h720_169,
          );
          break;
        case CaptureProfile.medium:
          options = CameraCaptureOptions(
            maxFrameRate: math.min(30, DeviceCapabilityService.getMaxFramerate()).toDouble(),
            params: VideoParametersPresets.h720_169,
          );
          break;
        case CaptureProfile.low:
          options = CameraCaptureOptions(
            maxFrameRate: math.min(18, DeviceCapabilityService.getMaxFramerate()).toDouble(),
            params: VideoParametersPresets.h360_169,
          );
      }

      // Recreate track with new options
      await _localVideoTrack?.stop();
      _localVideoTrack = await LocalVideoTrack.createCameraTrack(options);
      await _room!.localParticipant?.publishVideoTrack(_localVideoTrack!);
      notifyListeners();
      debugPrint('🎯 Applied capture profile: $profile');
    } catch (e) {
      debugPrint('❌ Failed to apply capture profile: $e');
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
    // Choose the minimum of device capability and network recommendation
    var finalBitrate = deviceMaxBitrate < networkBitrate ? deviceMaxBitrate : networkBitrate;
    var finalFramerate = networkBitrate < 600000
      ? (deviceMaxFramerate * 0.8).toInt()
      : deviceMaxFramerate;

    // Be more conservative on low-end devices
    if (DeviceCapabilityService.capability == DeviceCapability.lowEnd) {
      finalBitrate = (finalBitrate * 0.5).toInt(); // reduce bitrate further
      finalFramerate = math.min(finalFramerate, 18); // cap framerate for CPU savings
    }
    
    debugPrint('🎥 Video encoding: ${finalBitrate}bps, ${finalFramerate}fps, codec: $preferredCodec');
    
    if (kIsWeb) {
      // Web: VP9 optimization for better compression
      return VideoEncoding(
        maxBitrate: preferredCodec == 'VP9' ? finalBitrate : (finalBitrate * 0.8).toInt(),
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
      
      // Connect to room
      await _room!.connect(
        url,
        token,
        roomOptions: RoomOptions(
          defaultCameraCaptureOptions: CameraCaptureOptions(
            maxFrameRate: DeviceCapabilityService.getMaxFramerate().toDouble(),
            params: DeviceCapabilityService.capability == DeviceCapability.lowEnd
                ? VideoParametersPresets.h360_169
                : (DeviceCapabilityService.shouldUse1080p()
                    ? VideoParametersPresets.h1080_169
                    : VideoParametersPresets.h720_169),
          ),
          // Enhanced adaptive streaming and codec selection already enabled
          defaultScreenShareCaptureOptions: ScreenShareCaptureOptions(
            maxFrameRate: 15,
            params: VideoParametersPresets.h720_169,
          ),
          defaultAudioCaptureOptions: AudioCaptureOptions(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
            // Use Opus codec for better cross-platform audio
            // Lower sample rate for better compatibility
          ),
          defaultVideoPublishOptions: VideoPublishOptions(
            videoEncoding: _getOptimalVideoEncoding(),
          ),
          defaultAudioPublishOptions: AudioPublishOptions(
            audioBitrate: _networkService.getRecommendedAudioBitrate(),
          ),
          adaptiveStream: true,
          dynacast: true,
        ),
      );
      
      // Enable local tracks
      await enableCamera();
      await enableMicrophone();
      
      notifyListeners();
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
            params: DeviceCapabilityService.shouldUse1080p() 
                ? VideoParametersPresets.h1080_169 
                : VideoParametersPresets.h720_169,
          ),
        );
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
  
  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
