import 'package:livekit_client/livekit_client.dart';
import 'mediapipe_settings.dart';
import 'mediapipe_processor_stub.dart'
    if (dart.library.html) 'mediapipe_processor_web.dart'
    if (dart.library.io) 'mediapipe_processor_native.dart';

abstract class MediaPipeProcessor extends TrackProcessor<VideoProcessorOptions> {
  factory MediaPipeProcessor(MediaPipeSettings settings) =>
      createMediaPipeProcessor(settings);
}
