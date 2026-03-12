import 'package:flutter/foundation.dart';

/// Environment configuration for the app
/// 
/// After setting up Firebase with FlutterFire CLI, update the values below
/// with your actual project credentials.
class Environment {
  // App Configuration
  static const String appName = 'Tres';
  static const String appVersion = '1.0.0';
  
  // LiveKit Configuration
  // Self-hosted on OVHcloud VPS (Saves $8,040/year!)
  static const String liveKitUrl = String.fromEnvironment(
    'LIVEKIT_URL',
    defaultValue: 'wss://livekit.iptvsubz.fun',
  );

  // Optional comma-separated list of fallback LiveKit URLs for reconnects.
  static const String liveKitFallbackUrls = String.fromEnvironment(
    'LIVEKIT_FALLBACK_URLS',
    defaultValue: '',
  );

  // Optional JSON array of ICE servers for TURN/STUN overrides.
  // Example:
  // [{"urls":["turn:turn.example.com:3478"],"username":"user","credential":"pass"}]
  static const String liveKitIceServersJson = String.fromEnvironment(
    'LIVEKIT_ICE_SERVERS_JSON',
    defaultValue: '',
  );

  // Force TURN relay only if set (may increase latency).
  static const bool liveKitForceRelay = bool.fromEnvironment(
    'LIVEKIT_FORCE_RELAY',
    defaultValue: false,
  );
  
  // Firebase Functions Base URL
  // Format: https://REGION-PROJECT_ID.cloudfunctions.net
  // Example: https://us-central1-my-project.cloudfunctions.net
  static const String functionsBaseUrl = String.fromEnvironment(
    'FUNCTIONS_BASE_URL',
    defaultValue: 'https://us-central1-tres3-5fdba.cloudfunctions.net',
  );
  
  // Feature Flags
  static const bool enableMLFeatures = false;
  static const bool enableE2EEncryption = true;
  static const bool enableCloudRecording = false;
  static const bool enableScreenShare = false;
  static const bool enableBackgroundMode = true;
  
  // ML Configuration
  static const double backgroundBlurStrength = 0.85;
  static const int maxFacesDetected = 5;
  
  // Call Quality Settings
  static const int defaultVideoBitrate = 2000; // kbps
  static const int defaultAudioBitrate = 128; // kbps
  static const String defaultVideoResolution = '720p';
  static const int defaultFrameRate = 30;
  
  // Chat Configuration
  static const int maxMessageLength = 500;
  static const int maxChatHistory = 100;
  
  // Development Mode — defaults to false so production builds are safe by default.
  // Pass --dart-define=DEVELOPMENT=true for local development.
  static const bool isDevelopment = bool.fromEnvironment(
    'DEVELOPMENT',
    defaultValue: false,
  );
  
  // Debug Logging
  static const bool enableDebugLogging = kDebugMode;
  
  // API Endpoints
  static String get generateTokenEndpoint => '$functionsBaseUrl/generateGuestToken';
  /// Validate that all required configuration is set
  static bool validate() {
    if (liveKitUrl.contains('your-livekit-server.com')) {
      debugPrint('❌ LiveKit URL not configured');
      return false;
    }
    
    if (functionsBaseUrl.contains('YOUR_PROJECT_ID')) {
      debugPrint('❌ Firebase Functions URL not configured');
      return false;
    }
    
    return true;
  }
  
  /// Print current configuration (for debugging)
  static void printConfig() {
    if (!enableDebugLogging) return;
    
    debugPrint('=== Environment Configuration ===');
    debugPrint('App Name: $appName');
    debugPrint('App Version: $appVersion');
    debugPrint('LiveKit URL: $liveKitUrl');
    debugPrint('Functions Base URL: $functionsBaseUrl');
    debugPrint('ML Features: $enableMLFeatures');
    debugPrint('E2E Encryption: $enableE2EEncryption');
    debugPrint('Cloud Recording: $enableCloudRecording');
    debugPrint('Screen Share: $enableScreenShare');
    if (liveKitFallbackUrls.isNotEmpty) {
      debugPrint('LiveKit Fallback URLs: $liveKitFallbackUrls');
    }
    if (liveKitIceServersJson.isNotEmpty) {
      debugPrint('LiveKit ICE Servers: configured');
    }
    if (liveKitForceRelay) {
      debugPrint('LiveKit Force Relay: enabled');
    }
    debugPrint('Development Mode: $isDevelopment');
    debugPrint('================================');
  }
}
