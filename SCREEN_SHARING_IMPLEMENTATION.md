# Screen Sharing Implementation

## Summary
Screen sharing functionality has been successfully implemented in the Android app. The feature allows users to share their screen during video calls through the LiveKit SDK's native screen sharing capabilities.

## Implementation Details

### 1. Permissions & Manifest
- **Permission Added**: `FOREGROUND_SERVICE_MEDIA_PROJECTION` in `AndroidManifest.xml`
- **Foreground Service Type**: Updated `CallForegroundService` to include `mediaProjection` in `foregroundServiceType`

### 2. Activity Result Handler
Added `screenCaptureRequest` activity result launcher in `InCallActivity.kt`:
```kotlin
internal val screenCaptureRequest = registerForActivityResult(
    ActivityResultContracts.StartActivityForResult()
) { result ->
    if (result.resultCode == Activity.RESULT_OK && result.data != null) {
        lifecycleScope.launch {
            try {
                room.localParticipant.setScreenShareEnabled(true)
                // Success handling
            } catch (e: Exception) {
                // Error handling
            }
        }
    }
}
```

### 3. UI Integration
The screen sharing toggle is available in the in-call menu:
- **Menu Location**: Bottom-left dropdown menu (accessible via three-dot menu button)
- **Toggle Behavior**: 
  - When OFF → Requests MediaProjection permission and starts sharing
  - When ON → Stops screen sharing
- **Visual Feedback**: Icon changes color when active (green when sharing)

### 4. Permission Flow
1. User clicks "Share Screen" in menu
2. System shows MediaProjection permission dialog
3. If granted: LiveKit SDK starts capturing and streaming the screen
4. If denied: User sees toast notification and sharing is cancelled

### 5. LiveKit SDK Integration
- Uses LiveKit Android SDK version: **2.21.0**
- API: `room.localParticipant.setScreenShareEnabled(true/false)`
- The SDK handles MediaProjection internally via its `ScreenCaptureService`

## Code Changes

### Files Modified
1. **`app/src/main/AndroidManifest.xml`**
   - Added `FOREGROUND_SERVICE_MEDIA_PROJECTION` permission
   - Updated `CallForegroundService` foreground service type

2. **`app/src/main/java/com/example/tres3/InCallActivity.kt`**
   - Added `screenCaptureRequest` ActivityResultLauncher
   - Added `pendingScreenShareEnable` state flag
   - Integrated permission request in screen sharing toggle
   - Connected toggle to LiveKit's `setScreenShareEnabled` API

## Testing Notes

### Requirements
- Device must be running **Android 5.0 (API 21)** or higher for MediaProjection
- Screen sharing requires the user to grant permission via system dialog

### Expected Behavior
- ✅ First time: Permission dialog appears
- ✅ Permission granted: Screen sharing starts, icon turns green
- ✅ Toggle off: Screen sharing stops
- ✅ Permission denied: Toast notification, sharing cancelled

## Build Status
- **Compilation**: ✅ Successful
- **Build Type**: Debug
- **APK Sizes**:
  - arm64-v8a: 111 MB
  - armeabi-v7a: 88 MB
  - x86_64: 148 MB
  - x86: 132 MB

## Known Issues & Limitations
- Screen sharing requires foreground service, which is automatically managed by `CallForegroundService`
- LiveKit's `ScreenCaptureService` is included from the SDK and handles the actual capture
- System notification will be shown while screen sharing is active (Android requirement)

## Next Steps
1. **Test on physical device**: Verify MediaProjection permission flow
2. **Test screen sharing quality**: Validate frame rate and resolution
3. **Test with remote participants**: Confirm screen share is visible to others
4. **Test landscape mode**: Ensure UI toggle works in both orientations
5. **Test background scenarios**: Verify behavior when app moves to background during screen sharing

## References
- LiveKit Android SDK: https://github.com/livekit/client-sdk-android
- MediaProjection API: https://developer.android.com/reference/android/media/projection/MediaProjection
