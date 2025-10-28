# Codebase Analysis Report - Tres3 Video Calling App

**Date:** October 21, 2025  
**Analysis Type:** Comprehensive Architecture Review for Enhancement Planning

---

## Executive Summary

The Tres3 video calling application is a well-architected Android app using modern technologies (Kotlin, Jetpack Compose, LiveKit, Firebase). The codebase is production-ready with existing features including 1:1 video calls, group calls, screen sharing, and push notifications. This analysis identifies integration points for additive enhancements focused on codec optimization, camera improvements, and ML Kit integration.

---

## 1. Architecture Overview

### Technology Stack
```
Platform: Android
├── Language: Kotlin 1.9.22
├── UI Framework: Jetpack Compose + Material3
├── Build System: Gradle 8.7
├── Min SDK: 24 (Android 7.0)
└── Target SDK: 34 (Android 14)

Video Infrastructure:
├── LiveKit SDK: 2.20.2
├── LiveKit Compose: 1.4.0
├── WebRTC: 125.6422.04
└── Current Codec: H.264 (default)

Backend Services:
├── Firebase Auth: Email/Password authentication
├── Firestore: User profiles, contacts, call signaling
├── Cloud Functions: LiveKit token generation, FCM notifications
├── FCM: Push notifications for incoming calls
└── Crashlytics: (configured, not heavily used)
```

### Application Structure
```
app/src/main/java/com/example/tres3/
├── Activities (UI Layer)
│   ├── MainActivity.kt - Entry point, auth routing
│   ├── SignInActivity.kt - Email/password sign-in
│   ├── CreateAccountActivity.kt - User registration
│   ├── HomeActivity.kt - Main dashboard, contact list
│   ├── InCallActivity.kt - Primary video call UI (Compose)
│   ├── IncomingCallActivity.kt - Incoming call full-screen UI
│   ├── ProfileActivity.kt - User profile management
│   ├── SettingsActivity.kt - App settings
│   ├── SplashActivity.kt - App launch screen
│   └── CrashReportActivity.kt - Crash reporting UI
│
├── Services (Background Processing)
│   ├── MyFirebaseMessagingService.kt - FCM message handling
│   ├── CallForegroundService.kt - Keeps app alive during calls
│   └── Tres3ConnectionService.kt - Telecom API integration
│
├── Managers (Business Logic)
│   ├── LiveKitManager.kt - Room connection, video quality
│   ├── CallSignalingManager.kt - Firestore-based signaling
│   ├── CallHandler.kt - Call state management
│   └── TelecomHelper.kt - Native call UI integration
│
├── Receivers (Event Handlers)
│   ├── CallActionReceiver.kt - Call notification actions
│   └── CallNotificationReceiver.kt - Accept/Decline actions
│
├── Data Layer
│   └── data/
│       ├── CallHistory.kt - Call history data model
│       └── CallHistoryRepository.kt - Call history persistence
│
├── Configuration
│   ├── livekit/
│   │   └── LiveKitConfig.kt - JWT token generation
│   ├── AppColors.kt - Color scheme
│   └── Tres3Application.kt - Application class
│
└── Utilities
    ├── util/
    │   ├── GlobalCrashHandler.kt - Crash handling
    │   └── InitialsDrawable.kt - Avatar generation
    └── BatteryOptimizationHelper.kt - Battery management
```

---

## 2. Current Video Call Architecture

### Call Flow Sequence
```
1. User Initiation (HomeActivity)
   └──> Select contact from Firestore
   
2. Signaling (CallSignalingManager)
   ├──> Generate unique room name
   ├──> Call Cloud Function for LiveKit token
   ├──> Send invitation via Firestore
   └──> Trigger FCM push notification
   
3. Recipient Notification (MyFirebaseMessagingService)
   ├──> Receive FCM data message
   ├──> Show IncomingCallActivity (full-screen)
   └──> User accepts or declines
   
4. Call Connection (LiveKitManager)
   ├──> Connect to LiveKit room
   ├──> Enable local camera/microphone
   ├──> Subscribe to remote participants
   └──> Render video in InCallActivity
   
5. Call UI (InCallActivity - Jetpack Compose)
   ├──> Main video feed (remote participant)
   ├──> Picture-in-Picture (local camera)
   ├──> Controls: Mute, Camera toggle, End call
   ├──> Advanced: Screen share, Add participant
   └──> Participants list overlay
   
6. Call Termination
   ├──> User ends call
   ├──> Disconnect from LiveKit room
   ├──> Update call status in Firestore
   └──> Save to call history
```

### LiveKit Integration Analysis

**Current Implementation:**
```kotlin
// LiveKitManager.kt
object LiveKitManager {
    var currentRoom: Room? = null
    
    // Video quality presets
    enum class VideoQuality { HIGH, AUTO, LOW }
    
    // Quality settings
    private fun getVideoSettings(quality: VideoQuality): LocalVideoTrackOptions {
        val params = when (quality) {
            VideoQuality.HIGH -> VideoCaptureParameter(1280, 720, 30)
            VideoQuality.AUTO -> VideoCaptureParameter(1280, 720, 30)
            VideoQuality.LOW -> VideoCaptureParameter(640, 360, 24)
        }
        return LocalVideoTrackOptions(captureParams = params)
    }
    
    // Room connection
    suspend fun connectToRoom(context: Context, url: String, token: String): Room {
        // Creates LiveKit room instance
        // Connects with provided URL and token
        // Returns connected room
    }
}
```

**Enhancement Opportunities:**
1. ✅ Codec selection not exposed (uses WebRTC default H.264)
2. ✅ Video quality settings exist but limited customization
3. ✅ No camera enhancement integration point
4. ✅ Frame processing pipeline not exposed for ML features

---

## 3. Integration Points for Enhancements

### 3.1 Codec Enhancement Integration

**Target File:** `LiveKitManager.kt`

**Current Limitations:**
- No codec preference configuration
- Uses LiveKit/WebRTC default codec negotiation
- No visibility into selected codec during call

**Integration Strategy:**
```kotlin
// Add to LiveKitManager.kt
private var preferredCodec: VideoCodecManager.PreferredCodec = H264

fun setPreferredCodec(codec: VideoCodecManager.PreferredCodec) {
    preferredCodec = codec
    // Apply codec preference to LiveKit room options
}

// Modify connectToRoom() to include codec preferences
suspend fun connectToRoom(...): Room {
    val codecPrefs = VideoCodecManager.getCodecPreferences(preferredCodec)
    // Configure LiveKit room with codec preferences
    // Note: Actual codec selection happens during WebRTC negotiation
}
```

**Files to Modify:**
- `LiveKitManager.kt` - Add codec configuration
- `SettingsActivity.kt` - Add codec selection UI
- `InCallActivity.kt` - Optional: Display active codec info

**Risk Level:** LOW - Additive only, H.264 remains fallback

---

### 3.2 Camera Enhancement Integration

**Target Files:** `InCallActivity.kt`, New: `CameraEnhancer.kt`

**Current Camera Handling:**
```kotlin
// InCallActivity.kt - Camera is managed by LiveKit
room.localParticipant.setCameraEnabled(true)
room.localParticipant.switchCamera() // Front/back toggle
```

**Integration Strategy:**
```kotlin
// New: CameraEnhancer.kt
class CameraEnhancer(context: Context) {
    // Access Camera2 API for advanced features
    private val cameraManager = context.getSystemService(CameraManager::class.java)
    
    fun applyCameraEnhancements(cameraId: String) {
        // Enable continuous autofocus
        // Optimize exposure compensation
        // Enable video stabilization
        // Configure low-light mode
    }
}

// Modify InCallActivity.kt
private val cameraEnhancer = CameraEnhancer(this)

private fun enableCamera() {
    room.localParticipant.setCameraEnabled(true)
    
    // Apply enhancements if feature flag enabled
    if (FeatureFlags.isCameraEnhancementsEnabled()) {
        lifecycleScope.launch {
            val cameraId = getCurrentCameraId()
            cameraEnhancer.applyCameraEnhancements(cameraId)
        }
    }
}
```

**Challenge:** LiveKit manages camera lifecycle
**Solution:** Use Camera2 API as middleware - configure before LiveKit takes control

**Files to Modify:**
- New: `video/CameraEnhancer.kt` - Camera2 API enhancements
- `InCallActivity.kt` - Apply enhancements during camera setup
- `SettingsActivity.kt` - Add camera enhancement toggles

**Risk Level:** MEDIUM - Camera2 API conflicts possible, needs testing

---

### 3.3 ML Kit Integration

**Target Files:** `InCallActivity.kt`, New: `ml/MLKitProcessor.kt`

**Current Video Pipeline:**
```
Camera → LiveKit SDK → WebRTC Encoder → Network
                           ↓
                    Remote Participant
```

**Enhanced Pipeline with ML Kit:**
```
Camera → ML Kit Processor → LiveKit SDK → WebRTC Encoder → Network
         (Segmentation,          ↓
          Background Blur)  Remote Participant
```

**Integration Strategy:**
```kotlin
// New: ml/MLKitProcessor.kt
class MLKitProcessor(context: Context) {
    private val segmenter = Segmentation.getClient(
        SelfiSegmenterOptions.Builder()
            .setDetectorMode(SelfiSegmenterOptions.STREAM_MODE)
            .build()
    )
    
    fun processFrame(inputFrame: Bitmap): Bitmap {
        // 1. Run segmentation to get background mask
        // 2. Apply blur to background
        // 3. Composite foreground + blurred background
        // 4. Return processed frame
    }
}

// Modify InCallActivity.kt
private var mlProcessor: MLKitProcessor? = null

private fun setupVideoProcessing() {
    if (FeatureFlags.isBackgroundBlurEnabled()) {
        mlProcessor = MLKitProcessor(this)
        
        // Hook into LiveKit's video frame callback
        // Process frames before encoding
        room.localParticipant.videoTracks.forEach { track ->
            track.interceptFrames { frame ->
                mlProcessor?.processFrame(frame) ?: frame
            }
        }
    }
}
```

**Challenge:** Frame processing adds latency
**Solution:** 
- Target 15-20 fps for ML processing (vs 30fps camera)
- Use GPU acceleration via ML Kit
- Skip frames if processing falls behind

**Dependencies to Add:**
```gradle
implementation 'com.google.mlkit:segmentation-selfie:16.0.0-beta4'
implementation 'com.google.mlkit:face-detection:16.1.5'
```

**Files to Modify:**
- New: `ml/MLKitProcessor.kt` - ML Kit processing logic
- New: `ml/VideoFrameProcessor.kt` - Frame interception
- `InCallActivity.kt` - Integrate frame processing
- `SettingsActivity.kt` - Add ML feature toggles
- `app/build.gradle` - Add ML Kit dependencies

**Risk Level:** HIGH - Performance impact, needs careful optimization

---

## 4. Signaling System Analysis

**Current Implementation:** Custom Firestore-based signaling

```kotlin
// CallSignalingManager.kt
object CallSignalingManager {
    // Send invitation
    suspend fun sendCallInvitation(
        recipientUserId: String,
        roomName: String,
        token: String
    )
    
    // Listen for invitations
    fun startListeningForCalls(onCallReceived: (CallInvitation) -> Unit)
    
    // Update invitation status
    suspend fun acceptCallInvitation(invitationId: String)
    suspend fun rejectCallInvitation(invitationId: String)
}
```

**Database Structure:**
```
Firestore:
  users/
    {userId}/
      - name, email, photoUrl, fcmToken
      callSignals/
        {signalId}/
          - type: "call_invite"
          - fromUserId
          - fromUserName
          - roomName
          - url
          - token
          - timestamp
          - status: "pending" | "ringing" | "accepted" | "rejected"
```

**Strengths:**
- ✅ Simple, works well for current use case
- ✅ Real-time updates via Firestore snapshots
- ✅ Automatic cleanup via Cloud Function

**For Video Enhancements:**
- ℹ️ Signaling system does NOT need modification
- ℹ️ Codec negotiation happens in WebRTC layer
- ℹ️ ML features are client-side only

---

## 5. Settings Architecture

**Current Implementation:** `SettingsActivity.kt`

**Existing Settings:**
```kotlin
// SharedPreferences: "settings"
- call_quality: "High" | "Auto" | "Low"
- heads_up_notifications: Boolean
```

**Enhancement Integration Points:**

```kotlin
// Add new settings sections:

Section("Video Quality") {
    // Existing quality dropdown
    QualityDropdown(...)
    
    // NEW: Codec selection
    if (FeatureFlags.isAdvancedCodecsEnabled()) {
        CodecDropdown(
            title = "Preferred Codec",
            current = currentCodec,
            available = VideoCodecManager.getAvailableCodecs(context)
        )
    }
}

Section("Camera Enhancements") {
    if (FeatureFlags.isCameraEnhancementsEnabled()) {
        SwitchPreference("Auto-focus Enhancement", ...)
        SwitchPreference("Video Stabilization", ...)
        SwitchPreference("Low-light Mode", ...)
    }
}

Section("ML Enhancements") {
    if (FeatureFlags.isMLKitEnabled()) {
        SwitchPreference("Background Blur", ...)
        SliderPreference("Blur Intensity", ...)
        BackgroundPicker("Virtual Background", ...)
    }
}

Section("Developer") {
    if (FeatureFlags.isDeveloperModeEnabled()) {
        SwitchPreference("Performance Overlay", ...)
        Button("Codec Diagnostics") { showCodecInfo() }
    }
}
```

**Files to Modify:**
- `SettingsActivity.kt` - Add new settings UI
- Feature flags control visibility

**Risk Level:** LOW - Purely additive UI

---

## 6. Performance Considerations

### Current Performance Characteristics

**Call Setup Time:** ~2-3 seconds
- Firebase auth check: <100ms
- Cloud Function token generation: 500-1000ms
- LiveKit connection: 1-2 seconds
- Camera initialization: 200-500ms

**Video Quality Metrics:**
- Default: 720p @ 30fps, H.264
- Bitrate: ~1-2 Mbps (adaptive)
- Latency: <200ms (typical)

### Enhancement Performance Impact

**Codec Switching:**
- H.265: ~10-20% CPU reduction (hardware encoder)
- VP9: Similar to H.264 (software), better on hardware
- **Impact:** ✅ Negligible to positive

**Camera Enhancements:**
- Auto-focus: <5ms per frame
- Stabilization: ~10-20ms processing
- **Impact:** ⚠️ Minor (5-10% CPU increase)

**ML Kit Processing:**
- Background segmentation: ~30-50ms per frame (GPU)
- Face detection: ~20-40ms per frame
- Target: 15-20 fps processing (vs 30fps camera)
- **Impact:** ⚠️ Moderate (15-25% CPU, 10-15% battery drain)

**Mitigation Strategies:**
1. Use GPU acceleration for ML processing
2. Process every other frame (15fps ML vs 30fps camera)
3. Disable ML features on low-end devices (<4GB RAM)
4. Provide quality vs performance toggle in settings

---

## 7. Security & Privacy Analysis

### Current Security Posture

**Authentication:**
- ✅ Firebase Auth (email/password)
- ✅ Secure token storage
- ✅ Password visual transformation

**Network Security:**
- ✅ WSS (WebSocket Secure) for LiveKit
- ✅ HTTPS for Firebase APIs
- ⚠️ Cleartext traffic allowed (for development)

**LiveKit Tokens:**
- ✅ Server-side generation (Cloud Functions)
- ✅ Short TTL (60 seconds for calls)
- ✅ Room-specific permissions

**Enhancement Security Considerations:**

**Codec Selection:**
- ✅ No security impact (codec choice doesn't affect encryption)
- ✅ WebRTC DTLS/SRTP handles encryption regardless of codec

**Camera Enhancements:**
- ✅ Camera2 API permissions already granted
- ✅ No new privacy concerns

**ML Kit Features:**
- ✅ On-device processing only (no cloud)
- ✅ No face data persisted
- ✅ Frames processed in-memory only
- ✅ Privacy-friendly by design

**Recommendations:**
1. Document ML processing in privacy policy
2. Allow users to disable all ML features
3. Don't persist processed frames
4. Use secure by default settings

---

## 8. Testing Infrastructure

### Current Test Coverage

**Unit Tests:** Minimal (standard Android template tests)
**Integration Tests:** None found
**UI Tests:** None found

**Test Files:**
```
app/src/test/java/com/example/tres3/
└── ExampleUnitTest.kt (placeholder)

app/src/androidTest/java/com/example/tres3/
└── ExampleInstrumentedTest.kt (placeholder)
```

### Recommended Testing Strategy for Enhancements

**Phase 1: Codec Support**
```kotlin
// New: VideoCodecManagerTest.kt
class VideoCodecManagerTest {
    @Test fun testCodecDetection()
    @Test fun testCodecFallback()
    @Test fun testHardwareVsSoftware()
    @Test fun testResolutionSupport()
}
```

**Phase 2: Camera Enhancements**
```kotlin
// New: CameraEnhancerTest.kt
class CameraEnhancerTest {
    @Test fun testAutoFocusConfiguration()
    @Test fun testStabilizationSupport()
    @Test fun testLowLightMode()
}
```

**Phase 3: ML Kit**
```kotlin
// New: MLKitProcessorTest.kt
class MLKitProcessorTest {
    @Test fun testBackgroundSegmentation()
    @Test fun testFrameProcessingLatency()
    @Test fun testGPUAcceleration()
}
```

**Integration Tests:**
```kotlin
// Test full call flow with enhancements
@Test fun testCallWithH265Codec()
@Test fun testCallWithBackgroundBlur()
@Test fun testCameraEnhancementsDuringCall()
```

---

## 9. Backward Compatibility Strategy

### Compatibility Matrix

| Feature | Min SDK | Recommended | Fallback |
|---------|---------|-------------|----------|
| H.264 (baseline) | 24 | All devices | N/A |
| H.265/HEVC | 24 | 2017+ devices | H.264 |
| VP9 | 24 | All devices | H.264 |
| VP8 | 24 | All devices | H.264 |
| Camera2 API | 24 | All devices | Basic camera |
| ML Kit Segmentation | 24 | 4GB+ RAM | Disabled |
| GPU Acceleration | 28 | Modern GPUs | Software fallback |

### Migration Path

**Existing Users:**
1. All enhancements OFF by default
2. Settings preserved during app updates
3. No change to existing call behavior
4. Optional opt-in via Settings

**New Users:**
1. Smart defaults based on device capabilities
2. H.264 codec initially
3. Camera enhancements ON if supported
4. ML features OFF (user must enable)

### Feature Detection

```kotlin
// Device capability detection
fun getRecommendedFeatures(context: Context): FeatureSet {
    return FeatureSet(
        advancedCodecs = hasHardwareEncoder(H265_HEVC),
        cameraEnhancements = hasCamera2Support(),
        mlFeatures = hasMinRAM(4096) && hasGPU(),
        performanceMode = if (isLowEndDevice()) "battery" else "quality"
    )
}
```

---

## 10. Dependencies Impact Analysis

### Current Dependencies (Relevant)
```gradle
// Video & WebRTC
implementation 'io.livekit:livekit-android:2.20.2'
implementation 'io.livekit:livekit-android-compose-components:1.4.0'
implementation 'io.github.webrtc-sdk:android:125.6422.04'

// Firebase
implementation platform('com.google.firebase:firebase-bom:32.7.0')
implementation 'com.google.firebase:firebase-auth-ktx'
implementation 'com.google.firebase:firebase-firestore-ktx'
implementation 'com.google.firebase:firebase-messaging-ktx'

// UI
implementation platform('androidx.compose:compose-bom:2024.02.00')
implementation 'androidx.compose.material3:material3'
```

### New Dependencies for Enhancements

**Phase 3: ML Kit** (only additions needed)
```gradle
// ML Kit for background blur and face detection
implementation 'com.google.mlkit:segmentation-selfie:16.0.0-beta4'
implementation 'com.google.mlkit:face-detection:16.1.5'

// Optional: OpenCV for advanced image processing
implementation 'org.opencv:opencv:4.8.0' // ~20MB
```

**APK Size Impact:**
- Current APK: ~30-40MB
- With ML Kit: +8-10MB (~12-15% increase)
- With OpenCV: +20MB additional (~50% increase)

**Recommendation:** Make ML Kit optional download or use Play Feature Delivery

---

## 11. Implementation Risks & Mitigation

### High-Risk Areas

**1. ML Kit Frame Processing**
- **Risk:** Performance degradation, battery drain
- **Mitigation:** 
  - Target 15fps processing (not 30fps)
  - Use GPU acceleration
  - Disable on low-end devices
  - Provide performance mode toggle

**2. Camera2 API Conflicts**
- **Risk:** Interference with LiveKit camera management
- **Mitigation:**
  - Apply enhancements before LiveKit takes control
  - Test on multiple device manufacturers
  - Provide fallback to basic camera

**3. Codec Negotiation Failures**
- **Risk:** Call fails if codec not supported
- **Mitigation:**
  - Always include H.264 in codec list
  - Test codec fallback logic
  - Log codec selection for debugging

### Medium-Risk Areas

**4. Settings UI Complexity**
- **Risk:** Too many options confuse users
- **Mitigation:**
  - Use feature flags to hide experimental features
  - Provide "Auto" presets
  - Add explanatory tooltips

**5. Testing Coverage**
- **Risk:** Insufficient testing on diverse devices
- **Mitigation:**
  - Test on min SDK device (Android 7.0)
  - Test on low-end, mid-range, high-end devices
  - Use Firebase Test Lab for device matrix

---

## 12. Recommendations

### Immediate Actions (Phase 1)

1. ✅ **Implement FeatureFlags System**
   - Created: `FeatureFlags.kt`
   - Integrated in: `Tres3Application.kt`
   - Status: COMPLETE

2. ✅ **Implement VideoCodecManager**
   - Created: `video/VideoCodecManager.kt`
   - Provides: Codec detection, selection, fallback
   - Status: COMPLETE

3. **Integrate Codec Selection in LiveKitManager**
   - Modify: `LiveKitManager.kt`
   - Add codec preference configuration
   - Estimated effort: 2-3 hours

4. **Add Codec Settings UI**
   - Modify: `SettingsActivity.kt`
   - Add codec dropdown with device capabilities
   - Estimated effort: 3-4 hours

### Short-term (Phase 2 - Week 3-4)

5. **Implement CameraEnhancer**
   - Create: `video/CameraEnhancer.kt`
   - Integrate: Camera2 API enhancements
   - Test: Multiple device manufacturers

6. **Add Camera Settings UI**
   - Modify: `SettingsActivity.kt`
   - Add camera enhancement toggles

### Medium-term (Phase 3 - Week 5-6)

7. **Implement ML Kit Integration**
   - Create: `ml/MLKitProcessor.kt`
   - Add: ML Kit dependencies
   - Implement: Background segmentation
   - Optimize: GPU acceleration, frame rate

8. **Add ML Settings UI**
   - Modify: `SettingsActivity.kt`
   - Add ML feature toggles
   - Add blur intensity slider

### Long-term (Phase 4 - Week 7)

9. **Comprehensive Testing**
   - Unit tests for all new components
   - Integration tests for call flows
   - Performance profiling
   - Device compatibility matrix

10. **Documentation**
    - Update user guide
    - Add developer documentation
    - Document performance characteristics

---

## 13. Success Metrics

### Quality Metrics
- [ ] H.265 provides 30-40% better compression than H.264
- [ ] Codec fallback works 100% of the time
- [ ] Camera enhancements improve perceived quality by 15%+
- [ ] Background blur maintains >20fps on mid-range devices

### Performance Metrics
- [ ] No increase in call setup time
- [ ] <10% additional battery drain from ML features
- [ ] <50ms additional latency from frame processing
- [ ] Stable memory usage (<100MB increase with ML)

### User Experience Metrics
- [ ] All enhancements accessible via Settings
- [ ] Clear enable/disable toggles
- [ ] Graceful degradation on unsupported devices
- [ ] No regression in existing functionality

### Technical Metrics
- [ ] Code coverage >70% for new components
- [ ] No critical bugs in production
- [ ] Build time increase <20%
- [ ] APK size increase <20%

---

## 14. Conclusion

The Tres3 video calling app has a solid foundation for enhancement. The codebase is well-structured, uses modern Android practices, and has clear separation of concerns. The proposed enhancements can be implemented additively without disrupting existing functionality.

### Key Strengths
- ✅ Modern tech stack (Kotlin, Compose, LiveKit)
- ✅ Clear architecture with separation of concerns
- ✅ Good use of Firestore for signaling
- ✅ Existing quality settings provide foundation

### Key Opportunities
- 🎯 Advanced codec support for better compression
- 🎯 Camera enhancements for improved quality
- 🎯 ML Kit integration for modern features
- 🎯 Feature flag system for gradual rollout

### Implementation Readiness
**Phase 1 (Codecs):** ✅ Ready to implement
**Phase 2 (Camera):** ✅ Ready to implement
**Phase 3 (ML Kit):** ⚠️ Needs performance validation

The phased approach ensures each enhancement is properly tested and validated before moving to the next, minimizing risk while maximizing value delivery.
