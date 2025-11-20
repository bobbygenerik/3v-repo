import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:web/web.dart' as web;
// ignore: implementation_imports
import 'package:dart_webrtc/src/media_stream_track_impl.dart';

/// Bridge to access LiveKit's underlying web video elements for PiP
class WebPipBridge {
  
  /// Extract the MediaStream from a LiveKit VideoTrack on web
  /// This accesses the underlying MediaStreamTrack from flutter_webrtc
  static web.MediaStream? getMediaStreamFromTrack(VideoTrack? track) {
    if (!kIsWeb || track == null) return null;
    
    try {
      // Get the flutter_webrtc MediaStreamTrack
      final webrtcTrack = track.mediaStreamTrack;
      
      // Cast to MediaStreamTrackWeb to access the jsTrack
      if (webrtcTrack is MediaStreamTrackWeb) {
        // Create a new web MediaStream and add the track
        final mediaStream = web.MediaStream();
        mediaStream.addTrack(webrtcTrack.jsTrack);
        
        debugPrint('✅ Successfully extracted MediaStream from VideoTrack');
        return mediaStream;
      } else {
        debugPrint('⚠️ MediaStreamTrack is not MediaStreamTrackWeb');
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
        if (element is web.HTMLVideoElement) {
          result.add(element);
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
          if (srcObject is web.MediaStream) {
            debugPrint('✅ Found main video MediaStream');
            return srcObject;
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
