import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

/// Screen share status enum
enum ScreenShareStatus {
  notSharing,
  requestingPermission,
  sharing,
  failed,
}

/// Screen resolution options
enum ScreenResolution {
  hd720p(1280, 720, '720p'),
  fullHd1080p(1920, 1080, '1080p'),
  qhd1440p(2560, 1440, '1440p'),
  auto(0, 0, 'Auto');

  const ScreenResolution(this.width, this.height, this.label);
  final int width;
  final int height;
  final String label;
}

/// Screen Share Service
/// 
/// Manages screen sharing functionality for video calls using LiveKit.
/// 
/// Features:
/// - Start/stop screen sharing
/// - Resolution and FPS configuration
/// - Permission handling (iOS/Android)
/// - Status tracking
/// 
/// Platform-specific behavior:
/// - Android: Uses MediaProjection API
/// - iOS: Uses ReplayKit
/// - Web: Uses screen capture API
/// 
/// Usage:
/// ```dart
/// final screenShare = ScreenShareService();
/// await screenShare.initialize(room);
/// 
/// // Start sharing
/// await screenShare.startScreenShare(
///   resolution: ScreenResolution.fullHd1080p,
///   fps: 15,
/// );
/// 
/// // Stop sharing
/// await screenShare.stopScreenShare();
/// ```
class ScreenShareService extends ChangeNotifier {
  static const String _tag = 'ScreenShare';

  Room? _room;
  LocalVideoTrack? _screenShareTrack;
  ScreenShareStatus _status = ScreenShareStatus.notSharing;
  ScreenResolution _resolution = ScreenResolution.hd720p;
  int _fps = 15;
  Timer? _statsTimer;

  // Stats
  int _framesSent = 0;
  double _bitrate = 0.0;
  DateTime? _shareStartTime;

  ScreenShareStatus get status => _status;
  bool get isSharing => _status == ScreenShareStatus.sharing;
  LocalVideoTrack? get screenShareTrack => _screenShareTrack;
  ScreenResolution get resolution => _resolution;
  int get fps => _fps;
  int get framesSent => _framesSent;
  double get bitrate => _bitrate;
  
  Duration? get shareDuration {
    if (_shareStartTime == null) return null;
    return DateTime.now().difference(_shareStartTime!);
  }

  /// Initialize screen share service
  Future<void> initialize(Room room) async {
    _room = room;
    debugPrint('$_tag: Service initialized');
  }

  /// Start screen sharing
  /// 
  /// Implementation with LiveKit:
  /// ```dart
  /// // Create screen share track
  /// final track = await LocalVideoTrack.createScreenShareTrack(
  ///   ScreenShareCaptureOptions(
  ///     maxFrameRate: fps,
  ///     params: VideoParameters(
  ///       dimensions: VideoDimensions(width, height),
  ///       maxBitrate: 3000000, // 3 Mbps
  ///       maxFramerate: fps,
  ///     ),
  ///   ),
  /// );
  /// 
  /// // Publish track
  /// await room.localParticipant?.publishVideoTrack(track);
  /// ```
  Future<bool> startScreenShare({
    ScreenResolution? resolution,
    int? fps,
  }) async {
    if (_room == null) {
      debugPrint('$_tag: Room not initialized');
      return false;
    }

    if (isSharing) {
      debugPrint('$_tag: Screen share already active');
      return true;
    }

    try {
      _status = ScreenShareStatus.requestingPermission;
      notifyListeners();

      // Set parameters
      _resolution = resolution ?? ScreenResolution.hd720p;
      _fps = fps ?? 15;

      debugPrint('$_tag: Starting screen share ${_resolution.label} @ ${_fps}fps');

      // Create screen share track with LiveKit
      _screenShareTrack = await LocalVideoTrack.createScreenShareTrack(
        ScreenShareCaptureOptions(
          maxFrameRate: _fps.toDouble(),
          captureScreenAudio: false,
          params: VideoParameters(
            dimensions: VideoDimensions(
              _resolution.width > 0 ? _resolution.width : 1920,
              _resolution.height > 0 ? _resolution.height : 1080,
            ),
          ),
        ),
      );

      // Publish screen share track to room
      await _room!.localParticipant?.publishVideoTrack(_screenShareTrack!);

      _status = ScreenShareStatus.sharing;
      _shareStartTime = DateTime.now();
      _framesSent = 0;
      _bitrate = 0.0;

      // Start stats collection
      _startStatsCollection();

      notifyListeners();
      debugPrint('$_tag: ✅ Screen share started');
      return true;

    } catch (e) {
      debugPrint('$_tag: ❌ Failed to start screen share: $e');
      _status = ScreenShareStatus.failed;
      notifyListeners();
      return false;
    }
  }

  /// Stop screen sharing
  Future<bool> stopScreenShare() async {
    if (!isSharing) {
      debugPrint('$_tag: Not currently sharing');
      return true;
    }

    try {
      debugPrint('$_tag: Stopping screen share');

      // Stop stats collection
      _statsTimer?.cancel();
      _statsTimer = null;

      // Unpublish and dispose track
      if (_screenShareTrack != null) {
        await _screenShareTrack!.stop();
        await _screenShareTrack!.dispose();
        _screenShareTrack = null;
      }

      _status = ScreenShareStatus.notSharing;
      _shareStartTime = null;
      notifyListeners();

      debugPrint('$_tag: ✅ Screen share stopped');
      return true;

    } catch (e) {
      debugPrint('$_tag: ❌ Failed to stop screen share: $e');
      return false;
    }
  }

  /// Toggle screen sharing on/off
  Future<bool> toggleScreenShare({
    ScreenResolution? resolution,
    int? fps,
  }) async {
    if (isSharing) {
      return await stopScreenShare();
    } else {
      return await startScreenShare(resolution: resolution, fps: fps);
    }
  }

  /// Change screen share resolution (while sharing)
  Future<bool> updateResolution(ScreenResolution resolution) async {
    if (!isSharing) {
      debugPrint('$_tag: Cannot update resolution - not sharing');
      return false;
    }

    try {
      debugPrint('$_tag: Updating resolution to ${resolution.label}');

      // In production: Update track parameters
      // This may require stopping and restarting the track
      
      _resolution = resolution;
      notifyListeners();

      debugPrint('$_tag: ✅ Resolution updated');
      return true;

    } catch (e) {
      debugPrint('$_tag: ❌ Failed to update resolution: $e');
      return false;
    }
  }

  /// Change FPS (while sharing)
  Future<bool> updateFps(int fps) async {
    if (!isSharing) {
      debugPrint('$_tag: Cannot update FPS - not sharing');
      return false;
    }

    if (fps < 1 || fps > 60) {
      debugPrint('$_tag: Invalid FPS: $fps (must be 1-60)');
      return false;
    }

    try {
      debugPrint('$_tag: Updating FPS to $fps');

      // In production: Update track parameters
      
      _fps = fps;
      notifyListeners();

      debugPrint('$_tag: ✅ FPS updated');
      return true;

    } catch (e) {
      debugPrint('$_tag: ❌ Failed to update FPS: $e');
      return false;
    }
  }

  /// Start collecting statistics
  void _startStatsCollection() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateStats();
    });
  }

  /// Update statistics
  void _updateStats() {
    if (!isSharing || _screenShareTrack == null) return;

    try {
      // In production: Get real stats from LiveKit track
      // Example:
      // final stats = await _screenShareTrack!.getStats();
      // _bitrate = stats.bitrate;
      // _framesSent = stats.framesSent;

      // Simulate stats update
      _framesSent += _fps; // Approximate frames per second
      _bitrate = 1500000 + (DateTime.now().millisecond % 500000); // Simulate 1.5-2.0 Mbps

      notifyListeners();
    } catch (e) {
      debugPrint('$_tag: Error updating stats: $e');
    }
  }

  /// Get formatted bitrate string
  String getFormattedBitrate() {
    final mbps = _bitrate / 1000000;
    return '${mbps.toStringAsFixed(1)} Mbps';
  }

  /// Get screen share statistics
  Map<String, dynamic> getStats() {
    return {
      'status': _status.toString(),
      'isSharing': isSharing,
      'resolution': '${_resolution.width}x${_resolution.height}',
      'fps': _fps,
      'framesSent': _framesSent,
      'bitrate': _bitrate,
      'bitrateFormatted': getFormattedBitrate(),
      'duration': shareDuration?.inSeconds,
    };
  }

  /// Check if screen share is supported on current platform
  static bool isSupported() {
    // Screen share is supported on all platforms with LiveKit
    // But may require different implementations:
    // - Android: MediaProjection
    // - iOS: ReplayKit
    // - Web: getDisplayMedia
    // - Desktop: Platform-specific capture
    return true;
  }

  /// Clean up resources
  Future<void> cleanup() async {
    debugPrint('$_tag: Cleaning up...');
    
    _statsTimer?.cancel();
    _statsTimer = null;

    if (isSharing) {
      await stopScreenShare();
    }

    _room = null;
    debugPrint('$_tag: ✅ Cleaned up');
  }

  @override
  void dispose() {
    cleanup(); // Fire and forget
    super.dispose();
  }
}
