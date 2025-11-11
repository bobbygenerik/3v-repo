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
  // Self-hosted on Contabo VPS (Saves $8,040/year!)
  static const String liveKitUrl = String.fromEnvironment(
    'LIVEKIT_URL',
    defaultValue: 'wss://livekit.iptvsubz.fun',
  );

  // Firebase Functions Base URL
  // Format: https://REGION-PROJECT_ID.cloudfunctions.net
  // Example: https://us-central1-my-project.cloudfunctions.net
  static const String functionsBaseUrl = String.fromEnvironment(
    'FUNCTIONS_BASE_URL',
    defaultValue: 'https://us-central1-tres3-5fdba.cloudfunctions.net',
  );

  // Feature Flags
  static const bool enableMLFeatures = true;
  static const bool enableE2EEncryption = true;
  static const bool enableCloudRecording = true;
  static const bool enableScreenShare = true;
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

  // Recording Configuration
  static const int maxRecordingDuration = 3600; // 1 hour in seconds
  static const String recordingFormat = 'mp4';
  static const String recordingQuality = 'high';

  // Development Mode
  static const bool isDevelopment = bool.fromEnvironment(
    'DEVELOPMENT',
    defaultValue: true,
  );

  // Debug Logging
  static const bool enableDebugLogging = isDevelopment;

  // API Endpoints
  static String get generateTokenEndpoint =>
      '$functionsBaseUrl/generateGuestToken';
  static String get startRecordingEndpoint =>
      '$functionsBaseUrl/startRecording';
  static String get stopRecordingEndpoint => '$functionsBaseUrl/stopRecording';

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
    debugPrint('Development Mode: $isDevelopment');
    debugPrint('================================');
  }
}
