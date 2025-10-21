# Incoming Call Notification Troubleshooting

## Problem
Incoming call notifications not showing when app is closed or in background.

## Root Cause
FCM (Firebase Cloud Messaging) handles messages differently based on:
1. **Message type** (notification vs data-only)
2. **App state** (foreground, background, or killed)

## How FCM Works

### Notification Messages (notification + data)
- **Foreground:** `onMessageReceived()` is called ✅
- **Background:** System tray notification shown automatically ❌
- **Killed:** System tray notification shown automatically ❌
- **Problem:** We can't show IncomingCallActivity when app is in background/killed

### Data-Only Messages (data only, no notification)
- **Foreground:** `onMessageReceived()` is called ✅
- **Background:** `onMessageReceived()` is called ✅
- **Killed:** `onMessageReceived()` is called ✅
- **Solution:** We can programmatically launch IncomingCallActivity!

## Current Implementation

### 1. Cloud Function (`functions/index.js`)
```javascript
// Sends DATA-ONLY message with high priority
const message = {
  token: fcmToken,
  data: {
    type: 'call_invite',
    invitationId: signalId,
    fromUserId: callData.fromUserId,
    fromUserName: callData.fromUserName,
    roomName: callData.roomName,
    url: callData.url,
    token: callData.token
  },
  android: {
    priority: 'high',
    ttl: 60 * 1000 // 60 seconds
  }
};
```

### 2. FCM Service (`MyFirebaseMessagingService.kt`)
```kotlin
override fun onMessageReceived(message: RemoteMessage) {
    val data = message.data
    if (data["type"] == "call_invite") {
        // Launch IncomingCallActivity directly
        val intent = Intent(this, IncomingCallActivity::class.java).apply {
            putExtra("invitationId", data["invitationId"])
            putExtra("fromUserName", data["fromUserName"])
            // ... more extras
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivity(intent)
    }
}
```

### 3. Manifest Configuration
```xml
<!-- FCM Service -->
<service
    android:name=".MyFirebaseMessagingService"
    android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>

<!-- Incoming Call Activity -->
<activity
    android:name=".IncomingCallActivity"
    android:exported="true"
    android:launchMode="singleTop"
    android:showWhenLocked="true"
    android:turnScreenOn="true">
</activity>
```

## Common Issues & Solutions

### Issue 1: Notifications Still Not Showing

**Possible Causes:**
1. Battery optimization is blocking the app
2. App was force-stopped by user
3. FCM token not registered
4. Device in Doze mode

**Solutions:**

#### A. Request Battery Optimization Exemption
Add to `HomeActivity.onCreate()`:
```kotlin
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
    val intent = Intent()
    val packageName = packageName
    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
    if (!pm.isIgnoringBatteryOptimizations(packageName)) {
        intent.action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
        intent.data = Uri.parse("package:$packageName")
        startActivity(intent)
    }
}
```

#### B. Verify FCM Token Registration
Check Firestore:
```
users/{userId}/fcmToken
```
Should contain a valid token.

Check logs:
```kotlin
FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
    Log.d("FCM", "Token: ${task.result}")
}
```

#### C. Test FCM Delivery
Use Firebase Console > Cloud Messaging > Send test message
- Add FCM token
- Include data payload: `{ "type": "call_invite", ... }`

### Issue 2: App Doesn't Wake Screen

**Solution:** Ensure permissions in `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
<uses-permission android:name="android.permission.TURN_SCREEN_ON" />
<uses-permission android:name="android.permission.SHOW_WHEN_LOCKED" />
```

And activity attributes:
```xml
<activity
    android:showWhenLocked="true"
    android:turnScreenOn="true" />
```

### Issue 3: Notifications Work on WiFi but not Mobile Data

**Cause:** Some carriers block high-priority FCM messages to save battery.

**Solution:**
1. Use `priority: 'high'` in Cloud Function ✅
2. Keep message payload small (< 4KB) ✅
3. Test on multiple carriers

### Issue 4: Works on Some Devices, Not Others

**Manufacturer-Specific Issues:**

#### Xiaomi/MIUI
- Settings > Battery & Performance > Manage Apps Battery Usage
- Find your app > No restrictions

#### Huawei/EMUI
- Settings > Battery > App Launch
- Find your app > Manual management
- Enable all three options

#### Samsung
- Settings > Apps > Your App > Battery
- Optimize battery usage > All apps
- Turn off optimization for your app

#### OnePlus/OxygenOS
- Settings > Battery > Battery Optimization
- Find your app > Don't optimize

## Testing Checklist

- [ ] App in foreground - notifications received
- [ ] App in background - notifications received
- [ ] App killed (swipe away from recent apps) - notifications received
- [ ] Device locked - screen wakes up
- [ ] Device in Doze mode - notifications received
- [ ] WiFi connection - notifications received
- [ ] Mobile data connection - notifications received
- [ ] Multiple rapid calls - all notifications received
- [ ] FCM token persists after app restart
- [ ] Battery optimization disabled for app

## Debugging Commands

### View FCM Logs (Device)
```bash
adb logcat | grep -E "FCM|MyFirebase"
```

### View Cloud Function Logs
```bash
firebase functions:log
```

### Check FCM Token
```bash
adb shell am start -a android.intent.action.VIEW -d "fcm-test://token"
```

### Test High Priority Message
```bash
curl -X POST https://fcm.googleapis.com/v1/projects/vchat-46b32/messages:send \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{
    "message": {
      "token": "YOUR_FCM_TOKEN",
      "data": {
        "type": "call_invite",
        "invitationId": "test-123",
        "fromUserName": "Test User"
      },
      "android": {
        "priority": "high"
      }
    }
  }'
```

## Architecture Flow

```
User A initiates call
    ↓
CallSignalingManager.sendCallInvitation()
    ↓
Write to Firestore: users/{userId}/callSignals
    ↓
Cloud Function: sendCallNotification (TRIGGER)
    ↓
Fetch User B's FCM token from Firestore
    ↓
Send high-priority DATA-ONLY FCM message
    ↓
FCM delivers to User B's device (even if app killed)
    ↓
MyFirebaseMessagingService.onMessageReceived()
    ↓
Launch IncomingCallActivity with call data
    ↓
User B sees full-screen incoming call
```

## Key Points

1. ✅ **Data-only messages** ensure `onMessageReceived()` is always called
2. ✅ **High priority** ensures immediate delivery even in Doze mode
3. ✅ **Direct activity launch** bypasses notification tap requirement
4. ✅ **Wake lock permissions** ensure screen turns on
5. ✅ **Battery optimization exemption** prevents system from killing service

## Related Files

- `/functions/index.js` - Cloud Function for sending FCM
- `/app/src/main/java/.../MyFirebaseMessagingService.kt` - FCM receiver
- `/app/src/main/java/.../IncomingCallActivity.kt` - Incoming call UI
- `/app/src/main/AndroidManifest.xml` - Permissions and service registration
- `/app/src/main/java/.../HomeActivity.kt` - FCM token registration
