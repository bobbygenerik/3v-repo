import 'package:livekit_client/livekit_client.dart';

/// Stub for non-web platforms
class WebPipBridge {
  static dynamic getMediaStreamFromTrack(VideoTrack? track) => null;
  static List<dynamic> findLiveKitVideoElements() => [];
  static dynamic getMainVideoStream() => null;
}
