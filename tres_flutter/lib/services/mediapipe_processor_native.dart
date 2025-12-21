import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStreamTrack;
import 'mediapipe_settings.dart';
import 'mediapipe_processor.dart';

class _NativeMediaPipeProcessor extends TrackProcessor<VideoProcessorOptions>
    implements MediaPipeProcessor {
  static const MethodChannel _channel =
      MethodChannel('mediapipe_processor');

  final MediaPipeSettings _settings;
  MediaStreamTrack? _processedTrack;
  String? _trackId;

  _NativeMediaPipeProcessor(this._settings) {
    _settings.addListener(_pushSettings);
  }

  @override
  String get name => 'MediaPipeProcessor(native)';

  @override
  MediaStreamTrack? get processedTrack => _processedTrack;

  @override
  Future<void> init(VideoProcessorOptions options) async {
    _trackId = options.track.id;
    _processedTrack = options.track;
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod('attachProcessor', {
      'trackId': _trackId,
      'backgroundBlur': _settings.backgroundBlurEnabled,
      'beauty': _settings.beautyEnabled,
      'faceMesh': _settings.faceMeshEnabled,
      'faceDetection': _settings.faceDetectionEnabled,
      'blurIntensity': _settings.blurIntensity,
    });
  }

  @override
  Future<void> restart(VideoProcessorOptions options) async {
    _trackId = options.track.id;
    _processedTrack = options.track;
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod('attachProcessor', {
      'trackId': _trackId,
      'backgroundBlur': _settings.backgroundBlurEnabled,
      'beauty': _settings.beautyEnabled,
      'faceMesh': _settings.faceMeshEnabled,
      'faceDetection': _settings.faceDetectionEnabled,
      'blurIntensity': _settings.blurIntensity,
    });
  }

  @override
  Future<void> destroy() async {
    if (!Platform.isAndroid) {
      _settings.removeListener(_pushSettings);
      _processedTrack = null;
      return;
    }
    if (_trackId != null) {
      await _channel.invokeMethod('detachProcessor', {
        'trackId': _trackId,
      });
    }
    _settings.removeListener(_pushSettings);
    _processedTrack = null;
  }

  @override
  Future<void> onPublish(Room room) async {}

  @override
  Future<void> onUnpublish() async {}

  void _pushSettings() {
    if (_trackId == null) return;
    if (!Platform.isAndroid) return;
    _channel.invokeMethod('updateOptions', {
      'trackId': _trackId,
      'backgroundBlur': _settings.backgroundBlurEnabled,
      'beauty': _settings.beautyEnabled,
      'faceMesh': _settings.faceMeshEnabled,
      'faceDetection': _settings.faceDetectionEnabled,
      'blurIntensity': _settings.blurIntensity,
    });
  }
}

MediaPipeProcessor createMediaPipeProcessor(MediaPipeSettings settings) {
  return _NativeMediaPipeProcessor(settings);
}
