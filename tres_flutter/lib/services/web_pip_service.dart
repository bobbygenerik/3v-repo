import 'package:flutter/foundation.dart';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

/// Service to handle Picture-in-Picture for web platform
/// Shows the main participant's video in a floating PiP window when user switches tabs
class WebPipService {
  html.VideoElement? _pipVideoElement;
  bool _isPipActive = false;
  bool _autoEnterPipEnabled = true;
  html.MediaStream? _currentStream;
  
  /// Check if PiP is supported in this browser
  bool get isPipSupported {
    if (!kIsWeb) return false;
    try {
      // Check if document.pictureInPictureEnabled exists
      return js_util.getProperty(html.document, 'pictureInPictureEnabled') == true;
    } catch (e) {
      return false;
    }
  }
  
  /// Check if currently in PiP mode
  bool get isPipActive => _isPipActive;
  
  /// Enable/disable automatic PiP when user switches tabs
  void setAutoEnterPip(bool enabled) {
    _autoEnterPipEnabled = enabled;
  }
  
  /// Update the video stream being displayed in PiP
  void updateStream(html.MediaStream? stream) {
    _currentStream = stream;
    if (_pipVideoElement != null && stream != null) {
      _pipVideoElement!.srcObject = stream;
      _pipVideoElement!.play();
    }
  }
  
  /// Enter PiP mode with the current stream
  Future<bool> enterPip() async {
    if (!isPipSupported) {
      debugPrint('PiP not supported in this browser');
      return false;
    }
    
    if (_currentStream == null) {
      debugPrint('No video stream available for PiP');
      return false;
    }
    
    try {
      // Create video element if it doesn't exist
      if (_pipVideoElement == null) {
        _pipVideoElement = html.VideoElement()
          ..autoplay = true
          ..muted = false
          ..style.display = 'none'; // Hidden from page but available for PiP
        
        html.document.body?.append(_pipVideoElement!);
      }
      
      // Set the stream
      _pipVideoElement!.srcObject = _currentStream;
      await _pipVideoElement!.play();
      
      // Request PiP
      await js_util.promiseToFuture(
        js_util.callMethod(_pipVideoElement!, 'requestPictureInPicture', []),
      );
      
      _isPipActive = true;
      
      // Listen for PiP exit
      _pipVideoElement!.addEventListener('leavepictureinpicture', _handlePipExit);
      
      debugPrint('Entered PiP mode');
      return true;
    } catch (e) {
      debugPrint('Failed to enter PiP: $e');
      return false;
    }
  }
  
  /// Exit PiP mode
  Future<void> exitPip() async {
    if (!_isPipActive) return;
    
    try {
      // Exit PiP
      await js_util.promiseToFuture(
        js_util.callMethod(html.document, 'exitPictureInPicture', []),
      );
      
      debugPrint('Exited PiP mode');
    } catch (e) {
      debugPrint('Failed to exit PiP: $e');
    }
  }
  
  void _handlePipExit(html.Event event) {
    _isPipActive = false;
    _pipVideoElement?.removeEventListener('leavepictureinpicture', _handlePipExit);
    debugPrint('PiP mode exited');
  }
  
  /// Set up auto-enter PiP when user switches tabs
  void setupAutoEnterPip() {
    if (!isPipSupported || !_autoEnterPipEnabled) return;
    
    // Listen for visibility change (user switching tabs)
    html.document.addEventListener('visibilitychange', (event) {
      _handleVisibilityChange();
    });
  }
  
  void _handleVisibilityChange() async {
    if (html.document.hidden ?? false) {
      // User switched away from tab - enter PiP
      if (!_isPipActive && _autoEnterPipEnabled && _currentStream != null) {
        await enterPip();
      }
    } else {
      // User returned to tab - exit PiP
      if (_isPipActive) {
        await exitPip();
      }
    }
  }
  
  /// Clean up resources
  void dispose() {
    exitPip();
    _pipVideoElement?.remove();
    _pipVideoElement = null;
    _currentStream = null;
  }
}
