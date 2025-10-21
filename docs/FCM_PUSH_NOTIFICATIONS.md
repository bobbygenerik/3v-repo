# Background Call Notifications with FCM

## Overview

This document explains how the app receives incoming calls **even when closed or in the background** using Firebase Cloud Messaging (FCM).

---

## How It Works

### Without FCM (Previous Behavior)
❌ App must be open on HomeActivity to receive calls  
❌ If app is closed, no notification  
❌ Missed calls if recipient isn't actively using the app

### With FCM (New Behavior)
✅ Receives calls even when app is completely closed  
✅ Wakes up the device and shows incoming call screen  
✅ Works in background, foreground, and when app is killed  

---

## Architecture

```
Device A (Caller)                     Cloud Functions              Device B (Callee)
     │                                      │                              │
     │ 1. User clicks call button           │                              │
     │────────────────────────────────────> │                              │
     │                                      │                              │
     │ 2. Write to Firestore:               │                              │
     │    users/B/callSignals               │                              │
     │────────────────────────────────────> │                              │
     │                                      │                              │
     │                              3. Firestore trigger                   │
     │                              detects new callSignal                 │
     │                                      │                              │
     │                              4. Get user B's FCM token              │
     │                                      │                              │
     │                              5. Send FCM push notification          │
     │                                      │─────────────────────────────>│
     │                                      │                              │
     │                                      │         6. Device wakes up   │
     │                                      │         7. Launch IncomingCall
     │                                      │                              │
     │<──────────────────────────────── 8. User accepts ─────────────────>│
     │                                                                     │
     │<═════════════════════════ Video call connected ════════════════════│
```

---

## Components

### 1. Cloud Functions (`functions/index.js`)

#### `sendCallNotification`
- **Trigger:** Firestore onCreate listener on `users/{userId}/callSignals/{signalId}`
- **Purpose:** Send FCM push notification when someone initiates a call
- **Process:**
  1. Detects new call signal document
  2. Retrieves recipient's FCM token from Firestore
  3. Sends high-priority push notification with call data
  4. Logs success/failure

```javascript
exports.sendCallNotification = functions.firestore
  .document('users/{userId}/callSignals/{signalId}')
  .onCreate(async (snap, context) => {
    // Send push notification to recipient
  });
```

#### `cleanupOldCallSignals`
- **Trigger:** Scheduled function (runs every hour)
- **Purpose:** Delete call signals older than 1 hour
- **Benefits:** Keeps database clean, prevents stale notifications

---

### 2. Android App

#### `MyFirebaseMessagingService.kt`

**Key Methods:**

**`onMessageReceived(message: RemoteMessage)`**
- Receives FCM push notifications
- Extracts call invitation data
- Launches `IncomingCallActivity` with call details
- **Works even when app is closed!**

**`onNewToken(token: String)`**
- Called when FCM token is refreshed
- Saves token to Firestore for Cloud Functions to use
- Ensures user can always receive notifications

```kotlin
override fun onMessageReceived(message: RemoteMessage) {
    val data = message.data
    if (data["type"] == "call_invite") {
        // Launch IncomingCallActivity
        startActivity(intent)
    }
}
```

#### `HomeActivity.kt`

**`registerFCMToken()`**
- Called on app launch
- Gets current FCM token from Firebase
- Saves to Firestore: `users/{userId}/fcmToken`
- Enables Cloud Functions to send notifications

---

### 3. Notification Channels

For Android 8.0+ (API 26+), you need a notification channel:

**Channel ID:** `incoming_calls`  
**Importance:** HIGH  
**Sound:** Default ringtone  
**Vibration:** Enabled  
**Show on lock screen:** Yes

This should be created in your Application class or first Activity.

---

## Setup Instructions

### Step 1: Deploy Cloud Functions

```bash
cd /workspaces/3v-repo/functions

# Install dependencies (if not already installed)
npm install

# Deploy to Firebase
firebase deploy --only functions
```

**What gets deployed:**
- `sendCallNotification` - Sends push notifications
- `cleanupOldCallSignals` - Cleans up old signals
- `getLiveKitToken` - Generates LiveKit tokens (existing)

### Step 2: Verify Firestore Rules

Ensure `firestore.rules` includes:

```javascript
match /users/{userId} {
  allow read: if request.auth != null;
  allow write: if request.auth.uid == userId;
  
  match /callSignals/{signalId} {
    allow create: if request.auth != null;  // Anyone can send invites
    allow read, update, delete: if request.auth.uid == userId;
  }
}
```

### Step 3: Request Notification Permission

On Android 13+ (API 33+), you need to request notification permission.

**Add to HomeActivity or SplashActivity:**

```kotlin
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
        != PackageManager.PERMISSION_GRANTED) {
        
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST_CODE
        )
    }
}
```

### Step 4: Build and Test

```bash
# Build the app
./gradlew assembleDebug

# Install on both devices
adb -s DEVICE_A install -r app/build/outputs/apk/debug/app-debug.apk
adb -s DEVICE_B install -r app/build/outputs/apk/debug/app-debug.apk
```

---

## Testing

### Test 1: App Closed on Recipient
1. **Device A:** Sign in as User A
2. **Device B:** Sign in as User B
3. **Device B:** Close the app completely (swipe away from recent apps)
4. **Device A:** Call User B
5. **Expected:** Device B wakes up, shows IncomingCallActivity

### Test 2: App in Background
1. **Device B:** Open app, then minimize (home button)
2. **Device A:** Call User B
3. **Expected:** Device B shows IncomingCallActivity on top

### Test 3: Multiple Calls
1. Test accepting a call
2. Test rejecting a call
3. Test missing a call (timeout)

---

## Debugging

### Check FCM Token Registration

```bash
# Device A
adb -s DEVICE_A logcat | grep "FCM Token"
# Should show: FCM Token: eyJhbG...

# Verify in Firestore Console
# Navigate to: users/{userId}/fcmToken field
```

### Check Cloud Function Execution

```bash
# View function logs
firebase functions:log --only sendCallNotification

# Expected output:
# 📞 New call signal for user {userId} from {callerName}
# Sending push notification to FCM token: eyJhbG...
# ✅ Push notification sent successfully
```

### Check Android Logs

```bash
# Device B (recipient)
adb -s DEVICE_B logcat | grep -E "FCM|IncomingCall"

# Expected when call arrives:
# FCM: 📨 Message received from: ...
# FCM: 📞 Handling call invite
# FCM: ✅ Launched IncomingCallActivity
```

---

## Common Issues

### Issue 1: No notification received

**Symptoms:** Device B doesn't get notification when called

**Checks:**
1. Is FCM token saved in Firestore?
   - Check Firebase Console: `users/{userId}/fcmToken`
2. Are Cloud Functions deployed?
   - Run: `firebase functions:list`
3. Check function logs for errors:
   - Run: `firebase functions:log`
4. Is notification permission granted on Android 13+?

**Solutions:**
```bash
# Check token on device
adb logcat | grep "FCM Token"

# Re-deploy functions
firebase deploy --only functions

# Check Firestore write
# Firebase Console → Firestore → users/{userId}/callSignals
# Should see documents with status: "pending"
```

### Issue 2: Notification arrives but doesn't launch activity

**Symptoms:** Notification sound/vibration works, but no incoming call screen

**Possible causes:**
- Battery optimization blocking activity launch
- Missing `USE_FULL_SCREEN_INTENT` permission
- Activity not registered in manifest

**Solutions:**
1. Grant battery optimization exemption (app prompts for this)
2. Verify AndroidManifest has:
   ```xml
   <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
   ```
3. Check IncomingCallActivity registration

### Issue 3: Cloud Function not triggering

**Symptoms:** No logs in Firebase Functions console

**Checks:**
```bash
# Check function deployment
firebase functions:list

# Check Firestore writes are happening
# Firebase Console → Firestore → users/{userId}/callSignals
```

**Solutions:**
- Redeploy: `firebase deploy --only functions`
- Check billing: Cloud Functions require Blaze plan for Firestore triggers
- Verify Firestore rules allow writes

---

## Cost Considerations

### Firebase Cloud Functions Pricing

**Free tier (Spark plan):**
- ❌ No Firestore triggers
- ❌ No outbound networking

**Blaze plan (pay-as-you-go):**
- ✅ First 2 million invocations per month: FREE
- ✅ First 400,000 GB-seconds per month: FREE
- ✅ After free tier: ~$0.40 per million invocations

**Estimated costs for this app:**
- 100 calls/day = 3,000 calls/month
- 3,000 function invocations = **$0.00** (within free tier)
- Even at 1,000 calls/day = **$0.01/month**

### FCM Pricing
- ✅ Completely FREE
- No limits on messages sent

---

## Production Checklist

Before going live:

- [ ] Cloud Functions deployed: `firebase deploy --only functions`
- [ ] Firestore rules deployed: `firebase deploy --only firestore:rules`
- [ ] Firebase project on Blaze plan (for Firestore triggers)
- [ ] Notification permission requested in app
- [ ] Battery optimization exemption requested
- [ ] Tested with app closed on both Android and iOS
- [ ] Tested on different Android versions (API 26+)
- [ ] Verified FCM token registration logs
- [ ] Monitored Cloud Function execution logs

---

## Future Enhancements

### Priority 1: Notification Channel Setup
Add proper notification channel configuration in Application class:

```kotlin
class Tres3Application : Application() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }
    
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "incoming_calls",
                "Incoming Calls",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming video call notifications"
                enableVibration(true)
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .build()
                )
            }
            
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}
```

### Priority 2: Custom Ringtone
- Add custom ringtone to `res/raw/`
- Configure in notification channel

### Priority 3: Heads-Up Notification
- For Android 10+ when screen is on
- Shows banner at top of screen

### Priority 4: iOS Support
- Configure APNs (Apple Push Notification service)
- Update Cloud Functions to handle iOS tokens
- Test on iPhone devices

---

## Files Modified/Created

### New/Modified Files:
- `functions/index.js` - Added `sendCallNotification` and `cleanupOldCallSignals`
- `app/src/main/java/com/example/tres3/MyFirebaseMessagingService.kt` - Enhanced FCM handling
- `app/src/main/java/com/example/tres3/HomeActivity.kt` - Added FCM token registration
- `app/src/main/AndroidManifest.xml` - Added `WAKE_LOCK` and `USE_FULL_SCREEN_INTENT` permissions

### Documentation:
- `docs/FCM_PUSH_NOTIFICATIONS.md` (this file)

---

## Support

For issues:
1. Check Cloud Functions logs: `firebase functions:log`
2. Check device logcat: `adb logcat | grep -E "FCM|CallSignaling"`
3. Verify Firebase Console → Firestore → users/{userId}/fcmToken exists
4. Ensure Blaze plan is active on Firebase project

---

**Status:** ✅ Fully implemented and ready for testing  
**Requires:** Firebase Blaze plan for Firestore triggers  
**Last updated:** October 19, 2025
