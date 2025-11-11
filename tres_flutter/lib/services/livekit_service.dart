import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

/// LiveKit service managing room connections and participant tracks
/// Mirrors functionality from Android LiveKitManager.kt
class LiveKitService extends ChangeNotifier {
  Room? _room;
  LocalVideoTrack? _localVideoTrack;
  LocalAudioTrack? _localAudioTrack;

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

      // Connect to room
      await _room!.connect(
        url,
        token,
        roomOptions: const RoomOptions(
          defaultCameraCaptureOptions: CameraCaptureOptions(
            maxFrameRate: 30,
            params: VideoParametersPresets.h720_169,
          ),
          defaultAudioCaptureOptions: AudioCaptureOptions(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
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
      if (_room == null) return;

      // Create camera track if not exists
      if (_localVideoTrack == null) {
        _localVideoTrack = await LocalVideoTrack.createCameraTrack(
          const CameraCaptureOptions(
            maxFrameRate: 30,
            params: VideoParametersPresets.h720_169,
          ),
        );

        // Publish to room
        await _room!.localParticipant?.publishVideoTrack(_localVideoTrack!);
      }

      // Unmute
      await _localVideoTrack?.unmute();
      notifyListeners();
    } catch (e) {
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
      if (track != null) {
        // Toggle camera position
        await track.setCameraPosition(CameraPosition.front);
        // Note: LiveKit automatically toggles between front/back
        notifyListeners();
      }
    } catch (e) {
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
        debugPrint('Participant connected: ${event.participant.identity}');
        notifyListeners();
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        debugPrint('Participant disconnected: ${event.participant.identity}');
        notifyListeners();
      })
      ..on<TrackPublishedEvent>((event) {
        debugPrint('Track published: ${event.publication.sid}');
        notifyListeners();
      })
      ..on<TrackSubscribedEvent>((event) {
        debugPrint('Track subscribed: ${event.track.sid}');
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
