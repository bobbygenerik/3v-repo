import 'package:flutter/foundation.dart';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Service to handle Picture-in-Picture for web platform
/// Shows the main participant's video in a floating PiP window when user switches tabs
class WebPipService {
  web.HTMLVideoElement? _pipVideoElement;
  bool _isPipActive = false;
  bool _autoEnterPipEnabled = true;
  web.MediaStream? _currentStream;
  
  /// Check if PiP is supported in this browser
  bool get isPipSupported {
    if (!kIsWeb) return false;
    try {
      // Detect Safari PWA (standalone) — disable PiP there because it is
      // unreliable and often unsupported in iOS PWA contexts.
      try {
        final ua = web.window.navigator.userAgent.toLowerCase();
        final isSafari = ua.contains('safari') && !ua.contains('chrome') && !ua.contains('crios') && !ua.contains('fxios');
        bool isStandalone = false;
          try {
            final mm = web.window.matchMedia('(display-mode: standalone)');
            isStandalone = mm.matches;
          } catch (_) {}
        // Some iOS versions expose navigator.standalone
        try {
          final nav = web.window.navigator;
          final standalone = (nav as dynamic).standalone;
          if (standalone == true) isStandalone = true;
        } catch (_) {}

        if (isSafari && isStandalone) {
          return false; // disable PiP in Safari PWAs
        }
      } catch (_) {}

      return web.document.pictureInPictureEnabled;
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
  void updateStream(web.MediaStream? stream) {
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
        _pipVideoElement = web.HTMLVideoElement()
          ..autoplay = true
          ..muted = false;
        
        // Hide from page but available for PiP
        _pipVideoElement!.style.display = 'none';
        
        web.document.body?.append(_pipVideoElement!);
      }
      
      // Set the stream
      _pipVideoElement!.srcObject = _currentStream;
      await _pipVideoElement!.play().toDart;
      
      // Request PiP
      await _pipVideoElement!.requestPictureInPicture().toDart;
      
      _isPipActive = true;
      
      // Listen for PiP exit
      _pipVideoElement!.addEventListener('leavepictureinpicture', _handlePipExit.toJS);
      
      debugPrint('✅ Entered PiP mode');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to enter PiP: $e');
      return false;
    }
  }
  
  /// Exit PiP mode
  Future<void> exitPip() async {
    if (!_isPipActive) return;
    
    try {
      // Exit PiP
      await web.document.exitPictureInPicture().toDart;
      
      debugPrint('Exited PiP mode');
    } catch (e) {
      debugPrint('Failed to exit PiP: $e');
    }
  }
  
  void _handlePipExit(web.Event event) {
    _isPipActive = false;
    _pipVideoElement?.removeEventListener('leavepictureinpicture', _handlePipExit.toJS);
    debugPrint('PiP mode exited');
  }
  
  /// Set up auto-enter PiP when user switches tabs
  void setupAutoEnterPip() {
    if (!isPipSupported || !_autoEnterPipEnabled) return;
    
    // Listen for visibility change (user switching tabs)
    web.document.addEventListener('visibilitychange', (web.Event event) {
      _handleVisibilityChange();
    }.toJS);
  }
  
  void _handleVisibilityChange() async {
    if (web.document.hidden) {
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
