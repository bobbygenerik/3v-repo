// Centralized runtime feature flags for conservative / stability-first toggles.
class FeatureFlags {
  // Disable experimental MediaPipe processing by default for stability.
  static const bool enableMediaPipe = false;

  // Disable screen-share feature by default (inert stub kept).
  static const bool enableScreenShare = false;

  // Allow ultra/high quality presets (set to false to keep conservative defaults).
  static const bool enableUltraQuality = false;

  // Enable simulcast (default true for non-PWA environments).
  static const bool enableSimulcast = true;

  // Enable 3-layer simulcast ladder for 1:1 calls (720/1080/1440).
  // Default true but still gated by Safari PWA checks in runtime.
  static const bool enableSimulcastLadder = true;
  // Enable adaptive bitrate by default, but Safari PWA will still be conservative.
  static const bool enableAdaptiveBitrate = true;

  // Keep haptics disabled on Safari PWA by default.
  static const bool disableHapticsOnSafariPwa = true;

  // Picture-in-Picture behavior (can be disabled for PWA environments).
  static const bool enablePictureInPicture = true;
}
