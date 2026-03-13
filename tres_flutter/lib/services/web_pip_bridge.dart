import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:web/web.dart' as web;
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStreamTrack;

/// Bridge to access LiveKit's underlying web video elements for PiP
class WebPipBridge {
  
  /// Extract the MediaStream from a LiveKit VideoTrack on web
  /// This accesses the underlying MediaStreamTrack from flutter_webrtc
  static web.MediaStream? getMediaStreamFromTrack(VideoTrack? track) {
    if (!kIsWeb || track == null) return null;
    
    try {
      // Get the flutter_webrtc MediaStreamTrack
      final webrtcTrack = track.mediaStreamTrack;
      
      // Use dynamic access to get the jsTrack from the web implementation
      // ignore: avoid_dynamic_calls
      final dynamic webTrack = webrtcTrack;
      try {
        final jsTrack = webTrack.jsTrack;
        final mediaStream = web.MediaStream();
        mediaStream.addTrack(jsTrack as web.MediaStreamTrack);
        
        debugPrint('✅ Successfully extracted MediaStream from VideoTrack');
        return mediaStream;
      } catch (_) {
        debugPrint('⚠️ MediaStreamTrack does not expose jsTrack (non-web platform)');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Failed to extract MediaStream: $e');
      return null;
    }
  }
  
  /// Find all video elements on the page (LiveKit creates these for VideoTrackRenderer)
  static List<web.HTMLVideoElement> findLiveKitVideoElements() {
    if (!kIsWeb) return [];
    
    try {
      final videos = web.document.querySelectorAll('video');
      final result = <web.HTMLVideoElement>[];
      for (var i = 0; i < videos.length; i++) {
        final element = videos.item(i);
        if (element != null && element.isA<web.HTMLVideoElement>()) {
          result.add(element as web.HTMLVideoElement);
        }
      }
      return result;
    } catch (e) {
      debugPrint('Failed to find video elements: $e');
      return [];
    }
  }
  
  /// Get the MediaStream from the first playing video element (main participant)
  static web.MediaStream? getMainVideoStream() {
    if (!kIsWeb) return null;
    
    try {
      final videos = findLiveKitVideoElements();
      
      // Find the largest/first playing video (likely the main participant)
      for (final video in videos) {
        if (video.srcObject != null && !video.paused) {
          final srcObject = video.srcObject;
          if (srcObject != null && srcObject.isA<web.MediaStream>()) {
            debugPrint('✅ Found main video MediaStream');
            return srcObject as web.MediaStream;
          }
        }
      }
      
      debugPrint('No playing video found');
      return null;
    } catch (e) {
      debugPrint('Failed to get main video stream: $e');
      return null;
    }
  }
}
