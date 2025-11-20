import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

/// Bridge to access LiveKit's underlying web video elements for PiP
class WebPipBridge {
  
  /// Extract the MediaStream from a LiveKit VideoTrack on web
  /// This accesses the internal mediaStreamTrack property
  static html.MediaStream? getMediaStreamFromTrack(VideoTrack? track) {
    if (!kIsWeb || track == null) return null;
    
    try {
      // Access the underlying mediaStreamTrack from LiveKit's VideoTrack
      // LiveKit's VideoTrack wraps a MediaStreamTrack
      final jsTrack = js.JsObject.fromBrowserObject(track);
      final mediaStreamTrack = jsTrack['mediaStreamTrack'];
      
      if (mediaStreamTrack == null) {
        debugPrint('No mediaStreamTrack found on VideoTrack');
        return null;
      }
      
      // Create a MediaStream from the track
      final mediaStream = html.MediaStream();
      final jsMediaStream = js.JsObject.fromBrowserObject(mediaStream);
      jsMediaStream.callMethod('addTrack', [mediaStreamTrack]);
      
      debugPrint('✅ Successfully extracted MediaStream from VideoTrack');
      return mediaStream;
    } catch (e) {
      debugPrint('❌ Failed to extract MediaStream: $e');
      return null;
    }
  }
  
  /// Find all video elements on the page (LiveKit creates these for VideoTrackRenderer)
  static List<html.VideoElement> findLiveKitVideoElements() {
    if (!kIsWeb) return [];
    
    try {
      final videos = html.document.querySelectorAll('video');
      return videos.whereType<html.VideoElement>().toList();
    } catch (e) {
      debugPrint('Failed to find video elements: $e');
      return [];
    }
  }
  
  /// Get the MediaStream from the first playing video element (main participant)
  static html.MediaStream? getMainVideoStream() {
    if (!kIsWeb) return null;
    
    try {
      final videos = findLiveKitVideoElements();
      
      // Find the largest/first playing video (likely the main participant)
      for (final video in videos) {
        if (video.srcObject != null && !video.paused) {
          final srcObject = video.srcObject;
          if (srcObject is html.MediaStream) {
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
