@JS()
library;

import 'dart:js_interop';
import 'package:js/js.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStreamTrack;
// ignore: implementation_imports
import 'package:dart_webrtc/src/media_stream_track_impl.dart';
import 'mediapipe_settings.dart';
import 'mediapipe_processor.dart';

@JS('MediaPipeBridge')
external JSObject get _mediaPipeBridge;

extension type _Bridge(JSObject _) {
  external JSPromise init();
  external JSPromise createProcessedTrack(JSObject track, JSAny options);
  external void updateOptions(JSAny options);
  external void disposeProcessor();
}

class _WebMediaPipeProcessor extends TrackProcessor<VideoProcessorOptions>
    implements MediaPipeProcessor {
  final MediaPipeSettings _settings;
  MediaStreamTrack? _processedTrack;
  bool _initialized = false;

  _WebMediaPipeProcessor(this._settings) {
    _settings.addListener(_pushSettings);
  }

  @override
  String get name => 'MediaPipeProcessor(web)';

  @override
  MediaStreamTrack? get processedTrack => _processedTrack;

  @override
  Future<void> init(VideoProcessorOptions options) async {
    final bridge = _Bridge(_mediaPipeBridge);
    if (!_initialized) {
      await bridge.init().toDart;
      _initialized = true;
    }
    final jsOptions = _currentOptions();
    if (options.track is! MediaStreamTrackWeb) {
      throw StateError('MediaPipe requires a web MediaStreamTrack');
    }
    final jsTrack = (options.track as MediaStreamTrackWeb).jsTrack as JSObject;
    final processed = await bridge.createProcessedTrack(jsTrack, jsOptions).toDart;
    _processedTrack = MediaStreamTrackWeb(processed as dynamic);
  }

  @override
  Future<void> restart(VideoProcessorOptions options) async {
    await init(options);
  }

  @override
  Future<void> destroy() async {
    final bridge = _Bridge(_mediaPipeBridge);
    bridge.disposeProcessor();
    _settings.removeListener(_pushSettings);
    _processedTrack = null;
  }

  @override
  Future<void> onPublish(Room room) async {}

  @override
  Future<void> onUnpublish() async {}

  JSAny _currentOptions() {
    return {
      'backgroundBlur': _settings.backgroundBlurEnabled,
      'beauty': _settings.beautyEnabled,
      'faceMesh': _settings.faceMeshEnabled,
      'faceDetection': _settings.faceDetectionEnabled,
      'blurIntensity': _settings.blurIntensity,
    }.jsify() as JSAny;
  }

  void _pushSettings() {
    if (!_initialized) return;
    final bridge = _Bridge(_mediaPipeBridge);
    bridge.updateOptions(_currentOptions());
  }
}

MediaPipeProcessor createMediaPipeProcessor(MediaPipeSettings settings) {
  return _WebMediaPipeProcessor(settings);
}
