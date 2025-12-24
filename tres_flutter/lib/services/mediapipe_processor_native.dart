// Native MediaPipe bridge removed. Provide a small stub to avoid linking
// native processors.
import 'mediapipe_processor.dart';

MediaPipeProcessor createMediaPipeProcessor([dynamic _]) {
  throw UnsupportedError('MediaPipe has been removed from this build');
}
