import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Service to handle Android native Picture-in-Picture
class AndroidPipService {
  static const MethodChannel _channel = MethodChannel('tres3/pip');
  
  /// Check if PiP is available on this device
  static Future<bool> isPipAvailable() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    
    try {
      final bool available = await _channel.invokeMethod('isPipAvailable');
      return available;
    } catch (e) {
      debugPrint('Error checking PiP availability: $e');
      return false;
    }
  }
  
  /// Enter Picture-in-Picture mode
  static Future<bool> enterPipMode() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    
    try {
      final bool entered = await _channel.invokeMethod('enterPipMode');
      return entered;
    } catch (e) {
      debugPrint('Error entering PiP mode: $e');
      return false;
    }
  }
  
  /// Check if currently in PiP mode
  static Future<bool> isInPipMode() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    
    try {
      final bool inPip = await _channel.invokeMethod('isInPipMode');
      return inPip;
    } catch (e) {
      debugPrint('Error checking PiP mode: $e');
      return false;
    }
  }
}
