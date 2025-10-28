# Android Video Calling App - Enhancement Architecture

**Date:** October 21, 2025  
**Status:** Planning & Implementation Guide

## Executive Summary

This document outlines the architecture for enhancing the Tres3 Android video calling application with advanced codec support, camera optimizations, and ML Kit integration. All enhancements are **additive only** - preserving existing functionality while adding new capabilities through feature flags and middleware patterns.

---

## Current Architecture Analysis

### Existing Technology Stack
- **Platform**: Android (minSdk 24, targetSdk 34)
- **Language**: Kotlin 1.9.22
- **UI Framework**: Jetpack Compose with Material3
- **Video Infrastructure**: LiveKit Android SDK 2.20.2
- **WebRTC**: io.github.webrtc-sdk:android:125.6422.04
- **Backend**: Firebase (Auth, Firestore, Cloud Functions, FCM)
- **Signaling**: Custom Firestore-based signaling (CallSignalingManager)

### Current Video Capabilities
- **Codecs**: H.264 (default via WebRTC)
- **Quality Presets**: HIGH (720p@30fps), AUTO (adaptive), LOW (360p@24fps)
- **Features**: 
  - 1:1 and group video calls
  - Screen sharing
  - Picture-in-Picture mode
  - Participant management
  - Push notifications

### Integration Points
1. **LiveKitManager.kt** - Room connection and video quality management
2. **InCallActivity.kt** - Main call UI and media controls
3. **CallSignalingManager.kt** - Call invitation and signaling
4. **MyFirebaseMessagingService.kt** - Push notification handling
5. **functions/index.js** - Cloud Functions for token generation

---

## Enhancement Plan

### Phase 1: Advanced Codec Support

#### Objective
Enable H.265 (HEVC), VP9, and VP8 codec support while maintaining H.264 as default fallback.

#### Architecture

##### 1.1 Codec Configuration System
**New File**: `app/src/main/java/com/example/tres3/video/VideoCodecManager.kt`

```kotlin
/**
 * Manages video codec selection and configuration
 * Provides fallback mechanism to ensure compatibility
 */
object VideoCodecManager {
    enum class PreferredCodec {
        H264,      // Default, universal compatibility
        H265_HEVC, // Better compression, newer devices
        VP9,       // WebRTC optimized, good quality
        VP8        // WebRTC fallback, wide support
    }
    
    // Check device codec support
    fun getAvailableCodecs(): List<PreferredCodec>
    
    // Get codec parameters for LiveKit
    fun getCodecPreferences(preferred: PreferredCodec): VideoCodecPreferences
    
    // Validate codec support on device
    fun isCodecSupported(codec: PreferredCodec): Boolean
}
```

##### 1.2 Integration with LiveKitManager
**Modified**: `LiveKitManager.kt`

Add codec configuration without breaking existing quality system:
```kotlin
// Add to LiveKitManager
var preferredCodec: VideoCodecManager.PreferredCodec = 
    VideoCodecManager.PreferredCodec.H264 // Default

fun loadCodecFromSettings(context: Context) {
    val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
    val codecString = prefs.getString("preferred_codec", "H264") ?: "H264"
    preferredCodec = VideoCodecManager.PreferredCodec.valueOf(codecString)
}
```

##### 1.3 Settings UI Enhancement
**Modified**: `SettingsActivity.kt`

Add codec selection without modifying existing settings:
```kotlin
// New section in settings
Section("Video Quality") {
    // Existing quality dropdown
    QualityDropdown(...)
    
    // NEW: Codec preference dropdown
    CodecDropdown(
        current = currentCodec,
        available = VideoCodecManager.getAvailableCodecs(),
        onSelect = { codec -> 
            saveCodecPreference(codec)
        }
    )
}
```

#### Implementation Steps
1. Create VideoCodecManager with device capability detection
2. Integrate with LiveKitManager (additive)
3. Add codec selection UI to SettingsActivity
4. Add feature flag: `enable_advanced_codecs`
5. Test on multiple devices for compatibility

---

### Phase 2: Camera Optimization

#### Objective
Enhance camera quality using Camera2 API features for better focus, exposure, and stabilization.

#### Architecture

##### 2.1 Camera Enhancement Layer
**New File**: `app/src/main/java/com/example/tres3/video/CameraEnhancer.kt`

```kotlin
/**
 * Provides camera enhancements using Camera2 API
 * Works as middleware - doesn't replace LiveKit's camera management
 */
class CameraEnhancer(private val context: Context) {
    
    // Auto-focus enhancement
    fun enableContinuousAutoFocus(cameraId: String)
    
    // Exposure optimization
    fun optimizeExposure(cameraId: String)
    
    // Video stabilization
    fun enableStabilization(cameraId: String)
    
    // Low-light enhancement
    fun enableLowLightMode(cameraId: String)
    
    // Get camera capabilities
    fun getCameraCapabilities(cameraId: String): CameraCapabilities
}
```

##### 2.2 Integration Point
**Modified**: `InCallActivity.kt`

Add camera enhancements as optional layer:
```kotlin
// Initialize camera enhancer
private val cameraEnhancer = CameraEnhancer(this)

// Apply enhancements when camera starts
private fun setupCamera() {
    // Existing LiveKit camera setup
    room.localParticipant.setCameraEnabled(true)
    
    // NEW: Apply enhancements if enabled
    if (isCameraEnhancementEnabled()) {
        lifecycleScope.launch {
            cameraEnhancer.enableContinuousAutoFocus()
            cameraEnhancer.optimizeExposure()
            cameraEnhancer.enableStabilization()
        }
    }
}
```

##### 2.3 Settings Integration
**Modified**: `SettingsActivity.kt`

```kotlin
// New camera settings section
Section("Camera Enhancements") {
    SwitchPreference(
        title = "Auto-focus Enhancement",
        key = "camera_autofocus_enhanced"
    )
    SwitchPreference(
        title = "Video Stabilization",
        key = "camera_stabilization"
    )
    SwitchPreference(
        title = "Low-light Mode",
        key = "camera_lowlight"
    )
}
```

#### Implementation Steps
1. Create CameraEnhancer class with Camera2 API integration
2. Add capability detection for device support
3. Integrate as optional middleware in InCallActivity
4. Add settings UI for camera enhancements
5. Add feature flag: `enable_camera_enhancements`
6. Test on various devices and lighting conditions

---

### Phase 3: Google ML Kit Integration

#### Objective
Add ML-powered features like background blur, virtual backgrounds, and face detection.

#### Architecture

##### 3.1 ML Kit Processing Pipeline
**New File**: `app/src/main/java/com/example/tres3/ml/MLKitProcessor.kt`

```kotlin
/**
 * Manages ML Kit features for video enhancement
 * Processes video frames before sending to LiveKit
 */
class MLKitProcessor(private val context: Context) {
    
    // Background segmentation
    fun enableBackgroundBlur(intensity: Float)
    
    // Virtual background
    fun setVirtualBackground(backgroundImage: Bitmap)
    
    // Face detection and tracking
    fun enableFaceDetection(onFaceDetected: (Face) -> Unit)
    
    // Beauty filters (optional)
    fun applyBeautyFilter(level: Int)
    
    // Process video frame
    fun processFrame(inputFrame: Bitmap): Bitmap
}
```

##### 3.2 Video Frame Processing
**New File**: `app/src/main/java/com/example/tres3/ml/VideoFrameProcessor.kt`

```kotlin
/**
 * Intercepts video frames for ML processing
 * Works as middleware between camera and LiveKit
 */
class VideoFrameProcessor(
    private val mlKitProcessor: MLKitProcessor
) {
    
    fun processVideoFrame(frame: VideoFrame): VideoFrame {
        // Convert WebRTC VideoFrame to Bitmap
        val bitmap = frameToBitmap(frame)
        
        // Apply ML Kit processing
        val processed = mlKitProcessor.processFrame(bitmap)
        
        // Convert back to VideoFrame
        return bitmapToFrame(processed)
    }
}
```

##### 3.3 Integration with LiveKit
**Modified**: `InCallActivity.kt`

```kotlin
// Initialize ML Kit processor
private var mlKitProcessor: MLKitProcessor? = null
private var frameProcessor: VideoFrameProcessor? = null

private fun setupMLFeatures() {
    if (isMLKitEnabled()) {
        mlKitProcessor = MLKitProcessor(this)
        frameProcessor = VideoFrameProcessor(mlKitProcessor!!)
        
        // Apply background blur if enabled
        if (isBackgroundBlurEnabled()) {
            mlKitProcessor?.enableBackgroundBlur(0.7f)
        }
    }
}
```

##### 3.4 ML Kit Dependencies
**Modified**: `app/build.gradle`

```gradle
dependencies {
    // Existing dependencies...
    
    // Google ML Kit for video enhancements
    implementation 'com.google.mlkit:segmentation-selfie:16.0.0-beta4'
    implementation 'com.google.mlkit:face-detection:16.1.5'
    
    // OpenCV for image processing (if needed)
    implementation 'org.opencv:opencv:4.8.0'
}
```

##### 3.5 ML Kit Settings UI
**Modified**: `SettingsActivity.kt`

```kotlin
Section("ML Enhancements") {
    SwitchPreference(
        title = "Background Blur",
        summary = "Blur your background during calls",
        key = "ml_background_blur"
    )
    
    SliderPreference(
        title = "Blur Intensity",
        key = "ml_blur_intensity",
        min = 0,
        max = 100,
        enabled = isBackgroundBlurEnabled
    )
    
    // Virtual background selector
    BackgroundSelector(
        title = "Virtual Background",
        key = "ml_virtual_background"
    )
    
    SwitchPreference(
        title = "Face Enhancement",
        summary = "Auto-adjust focus and exposure for faces",
        key = "ml_face_enhancement"
    )
}
```

#### Implementation Steps
1. Add ML Kit dependencies to build.gradle
2. Create MLKitProcessor class with segmentation support
3. Create VideoFrameProcessor for frame interception
4. Integrate with InCallActivity as optional middleware
5. Add ML Kit settings UI
6. Add feature flags: `enable_ml_features`, `enable_background_blur`
7. Optimize for performance (use GPU acceleration)
8. Test on various devices for performance impact

---

## Feature Flag System

### Implementation
**New File**: `app/src/main/java/com/example/tres3/FeatureFlags.kt`

```kotlin
/**
 * Centralized feature flag management
 * Allows gradual rollout and A/B testing
 */
object FeatureFlags {
    private lateinit var prefs: SharedPreferences
    
    fun init(context: Context) {
        prefs = context.getSharedPreferences("feature_flags", Context.MODE_PRIVATE)
    }
    
    // Codec enhancements
    fun isAdvancedCodecsEnabled(): Boolean = 
        prefs.getBoolean("enable_advanced_codecs", false)
    
    // Camera enhancements
    fun isCameraEnhancementsEnabled(): Boolean = 
        prefs.getBoolean("enable_camera_enhancements", false)
    
    // ML Kit features
    fun isMLKitEnabled(): Boolean = 
        prefs.getBoolean("enable_ml_features", false)
    
    fun isBackgroundBlurEnabled(): Boolean = 
        isMLKitEnabled() && prefs.getBoolean("ml_background_blur", false)
    
    // Developer mode for testing
    fun isDeveloperModeEnabled(): Boolean = 
        prefs.getBoolean("developer_mode", false)
}
```

---

## Testing Strategy

### Unit Tests
```kotlin
// New test files
- VideoCodecManagerTest.kt
- CameraEnhancerTest.kt
- MLKitProcessorTest.kt
```

### Integration Tests
```kotlin
// Test codec switching
- testCodecFallback()
- testCodecQualityMetrics()

// Test camera enhancements
- testAutoFocusEnhancement()
- testStabilization()

// Test ML Kit features
- testBackgroundBlur()
- testVirtualBackground()
```

### Performance Tests
- Video quality metrics (PSNR, SSIM)
- Frame processing latency
- Battery consumption
- CPU/GPU usage
- Memory usage

---

## Backward Compatibility

### Guarantees
1. **Default Behavior**: All enhancements OFF by default
2. **Fallback Mechanism**: H.264 fallback if advanced codecs fail
3. **Graceful Degradation**: Disable ML Kit on low-end devices
4. **Existing Features**: No changes to existing call flow
5. **Settings Migration**: Preserve existing user preferences

### Device Support Matrix
| Feature | Min SDK | Recommended Device |
|---------|---------|-------------------|
| H.265/HEVC | 24 | Devices with hardware encoder |
| VP9 | 24 | All devices (software fallback) |
| Camera Enhancements | 24 | Camera2 API support |
| ML Kit | 24 | 4GB+ RAM recommended |
| Background Blur | 24 | GPU acceleration recommended |

---

## Security Considerations

### Video Processing
- **Frame Data**: Process frames in-memory only, never persist
- **ML Models**: Use on-device ML Kit models (no cloud processing)
- **Codec Selection**: Validate codec support to prevent crashes

### Privacy
- **Background Blur**: Process locally, no data sent to servers
- **Face Detection**: On-device only, no face data stored
- **Settings**: Store preferences locally, encrypted if needed

---

## Performance Optimization

### Best Practices
1. **Codec Selection**: Prefer hardware encoders over software
2. **ML Processing**: Use GPU acceleration where available
3. **Frame Rate**: Limit ML processing to 15-20 fps to save battery
4. **Quality vs Performance**: Provide user controls for trade-offs
5. **Memory Management**: Release resources when not in call

### Monitoring
- Add performance metrics logging
- Monitor battery drain
- Track frame drop rates
- Measure encoding latency

---

## Implementation Timeline

### Phase 1: Codec Support (Week 1-2)
- [ ] Day 1-2: Create VideoCodecManager
- [ ] Day 3-4: Integrate with LiveKitManager
- [ ] Day 5-6: Add Settings UI
- [ ] Day 7-8: Testing and optimization
- [ ] Day 9-10: Documentation and review

### Phase 2: Camera Enhancements (Week 3-4)
- [ ] Day 1-2: Create CameraEnhancer
- [ ] Day 3-4: Integrate with InCallActivity
- [ ] Day 5-6: Add Settings UI
- [ ] Day 7-8: Testing on multiple devices
- [ ] Day 9-10: Performance optimization

### Phase 3: ML Kit Integration (Week 5-6)
- [ ] Day 1-3: Add ML Kit dependencies and setup
- [ ] Day 4-6: Create MLKitProcessor and frame processing
- [ ] Day 7-8: Integrate with video pipeline
- [ ] Day 9-10: Add Settings UI
- [ ] Day 11-12: Performance testing and optimization

### Phase 4: Final Integration & Testing (Week 7)
- [ ] Day 1-2: Integration testing of all features
- [ ] Day 3-4: Performance profiling
- [ ] Day 5: Security review
- [ ] Day 6-7: Bug fixes and polish

---

## Success Metrics

### Quality Metrics
- [ ] H.265 provides 30-40% better compression than H.264
- [ ] VP9 provides comparable quality to H.264 at lower bitrates
- [ ] Camera enhancements improve focus time by 20%
- [ ] Background blur maintains 30fps on mid-range devices

### Performance Metrics
- [ ] <10% additional battery drain from ML features
- [ ] <50ms additional latency from frame processing
- [ ] No increase in call setup time
- [ ] Stable memory usage (<100MB increase)

### User Experience
- [ ] All features accessible via Settings
- [ ] Clear on/off toggle for each enhancement
- [ ] Graceful degradation on unsupported devices
- [ ] Existing functionality unaffected

---

## Conclusion

This architecture ensures that all enhancements are:
1. **Additive**: No existing functionality is modified or removed
2. **Optional**: All features behind feature flags and user settings
3. **Backward Compatible**: Default behavior unchanged
4. **Performant**: Optimized for minimal impact on resources
5. **Secure**: All processing happens on-device

The modular design allows for incremental implementation and testing, with each phase building on the previous while maintaining system stability.
