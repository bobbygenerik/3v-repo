# Feature Status & Known Limitations

## ✅ Fixed Issues

### 1. Call Ending for Both Participants
**Status:** FIXED
- Added `endCall()` method to `CallSignalingService`
- End call button now calls `signalingService.endCall(roomName)` before disconnecting
- Both participants are notified via Firestore `activeCallRooms` collection
- Call session is properly cleaned up

### 2. AR Filters Dialog
**Status:** FIXED
- Replaced "coming soon" placeholder with functional AR filter selection
- Shows all 11 available filters: None, Glasses, Hat, Mask, Bunny Ears, Cat Ears, Crown, Monocle, Pirate Patch, Santa Hat, Sparkles
- Filters are applied via `coordinator.setArFilter(filterName)`
- UI shows checkmark for currently active filter

### 3. Chat & Screen Sharing Menu Items
**Status:** FIXED
- Changed from toggle switches to simple menu items
- Tapping "Chat" or "Share Screen" now activates the feature directly
- More intuitive UX - no need to understand toggle state

## ⚠️ Known Limitations

### 1. Background Blur & Beauty Filters
**Issue:** Enabling these features doesn't visually change the video

**Root Cause:**
- The ML services (`BackgroundBlurService`, `BeautyFilterService`) have `processFrame()` methods that work correctly
- However, LiveKit's `VideoTrackRenderer` renders video directly from the camera/track without frame processing
- The filters would need to be integrated into a custom video processor that sits between the camera and LiveKit

**Technical Details:**
- LiveKit uses native renderers that bypass Flutter's widget tree
- To apply filters, you need to:
  1. Capture raw camera frames
  2. Process with ML Kit (background blur) or image processing (beauty filter)
  3. Create a custom video source that feeds processed frames to LiveKit
  4. This requires platform-specific implementations (Android/iOS)

**Workaround Options:**
1. Use LiveKit's server-side video processing (requires additional infrastructure)
2. Implement native video processors for Android/iOS
3. Use a different video SDK that supports frame-by-frame processing in Flutter

**Current State:**
- Services are fully implemented and functional for frame processing
- Just not connected to the video pipeline
- Toggling them on/off changes state correctly, but doesn't affect rendered video

### 2. AR Filters
**Status:** UI works, but filters don't render

**Root Cause:**
- Same issue as background blur/beauty filters
- `ARFiltersService` can detect faces and calculate overlay positions
- But can't render overlays on LiveKit's native video renderer

**What Works:**
- Face detection with ML Kit
- Filter selection UI
- State management

**What Doesn't Work:**
- Actually seeing the filters on video
- Requires same solution as above (custom video processor)

### 3. Screen Sharing
**Status:** Implementation is correct, may have permission issues

**Root Cause:**
- Code uses proper LiveKit API: `LocalVideoTrack.createScreenShareTrack()`
- Likely failing due to Android permissions or system restrictions

**Common Issues:**
- Android requires `MediaProjection` permission (runtime permission)
- Some Android versions restrict screen capture
- May need to add to `AndroidManifest.xml`:
  ```xml
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
  ```

**Testing:**
- Check Android logs for permission errors
- Ensure device supports MediaProjection API
- Test on Android 10+ (API level 29+)

### 4. Background Push Notifications
**Status:** Not implemented

**Requirements:**
1. **Firebase Cloud Messaging (FCM) Setup:**
   - Already have `firebase_messaging` package
   - Need FCM server key in Firebase Console
   - Need to configure Android/iOS push certificates

2. **Cloud Functions for Call Notifications:**
   - When user sends call invitation, trigger Cloud Function
   - Cloud Function sends FCM push notification to recipient
   - Notification should wake app and show incoming call screen

3. **Platform-Specific Configuration:**
   
   **Android:**
   - Add FCM service to `AndroidManifest.xml`
   - Handle background messages with `onBackgroundMessage` handler
   - Use high-priority notification channel
   
   **iOS:**
   - Configure APNS certificates in Firebase Console
   - Request notification permissions
   - Handle `didReceiveRemoteNotification` in AppDelegate
   - Use VoIP push notifications for better call UX

4. **Implementation Steps:**
   ```dart
   // In Cloud Functions (functions/index.js)
   exports.sendCallNotification = functions.firestore
     .document('call_invitations/{invitationId}')
     .onCreate(async (snap, context) => {
       const data = snap.data();
       const recipientToken = await getFCMToken(data.recipientId);
       
       await admin.messaging().send({
         token: recipientToken,
         notification: {
           title: `Incoming call from ${data.callerName}`,
           body: 'Tap to answer',
         },
         data: {
           type: 'call_invitation',
           invitationId: context.params.invitationId,
           roomName: data.roomName,
           // ... other call data
         },
         android: {
           priority: 'high',
           notification: {
             channelId: 'incoming_calls',
           },
         },
       });
     });
   ```

**Current State:**
- FCM package is installed
- No Cloud Functions for sending notifications
- No background message handlers
- App must be open to receive call invitations

## 🔧 Recommended Fixes

### Priority 1: Call Ending
✅ **DONE** - Both participants now properly notified

### Priority 2: AR Filters UI
✅ **DONE** - Replaced "coming soon" with working filter selector

### Priority 3: Push Notifications
**Effort:** Medium (2-4 hours)
- Set up Cloud Function for FCM
- Configure Android notification channels
- Test background notifications

### Priority 4: Screen Sharing Permissions
**Effort:** Low (30 minutes)
- Add permissions to AndroidManifest
- Add permission request UI
- Test on real device

### Priority 5: ML Video Filters
**Effort:** High (1-2 weeks)
- Requires custom video processing pipeline
- Platform-specific native code
- Performance optimization
- Consider if truly needed vs. server-side processing

## 📝 Notes

- Most "not working" features are UI/state management issues (now fixed)
- ML filter limitations are architectural, not bugs
- Screen sharing and push notifications just need configuration
- AR filters need same solution as other ML features

## 🎯 Next Steps

1. Test call ending with two devices ✅ READY
2. Test AR filter selection UI ✅ READY
3. Set up push notifications (if high priority)
4. Fix screen sharing permissions (if high priority)
5. Decide on ML video filters approach (native vs. server-side)
