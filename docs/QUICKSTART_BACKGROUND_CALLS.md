# 🚀 Quick Start Guide - Background Call Support

## What's New

Your app now supports **incoming calls even when closed**! 📞

---

## ⚠️ IMPORTANT: Deploy Cloud Functions First

Before testing, you **MUST** deploy the Cloud Functions:

```bash
cd /workspaces/3v-repo/functions
firebase deploy --only functions
```

**Why?** The Cloud Functions send push notifications when someone calls you. Without them, calls only work when the app is open.

---

## Prerequisites

### 1. Firebase Blaze Plan Required

Cloud Functions with Firestore triggers require the **Blaze (pay-as-you-go) plan**.

**To upgrade:**
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Click "Upgrade" in the bottom left
4. Choose "Blaze" plan

**Don't worry about cost:**
- First 2 million function calls per month: FREE
- Your usage will likely be under 10,000/month = $0
- Even 100,000 calls/month = ~$0.05

### 2. Check Firebase Project

```bash
# Verify you're logged in
firebase login

# Check which project you're using
firebase use

# If wrong project, switch to correct one
firebase use --add
```

---

## Deployment Steps

### Step 1: Deploy Cloud Functions

```bash
# Navigate to functions directory
cd /workspaces/3v-repo/functions

# Install dependencies (first time only)
npm install

# Deploy to Firebase
firebase deploy --only functions
```

**Expected output:**
```
✔  functions[sendCallNotification(us-central1)] Successful create operation.
✔  functions[cleanupOldCallSignals(us-central1)] Successful create operation.
✔  functions[getLiveKitToken(us-central1)] Successful update operation.

✔  Deploy complete!
```

### Step 2: Build Android App

```bash
# Return to project root
cd /workspaces/3v-repo

# Build the app
./gradlew assembleDebug
```

### Step 3: Install on Devices

```bash
# If you have one device connected
adb install -r app/build/outputs/apk/debug/app-debug.apk

# If you have multiple devices
adb devices  # List connected devices
adb -s DEVICE_SERIAL install -r app/build/outputs/apk/debug/app-debug.apk
```

---

## Testing

### Test 1: Background Call Reception

1. **Device A:** Sign in as User A
2. **Device B:** Sign in as User B, then **CLOSE the app completely**
   - Press home button
   - Swipe away app from recent apps
3. **Device A:** Call User B
4. **Expected Result:** Device B wakes up and shows incoming call screen

### Test 2: App in Background

1. **Device B:** Open app, press home button (don't close)
2. **Device A:** Call User B
3. **Expected:** Incoming call appears on Device B

### Test 3: App in Foreground

1. **Device B:** Keep app open on home screen
2. **Device A:** Call User B
3. **Expected:** Incoming call appears immediately

---

## Verification

### Check Cloud Functions Deployed

```bash
firebase functions:list
```

**Expected output:**
```
┌──────────────────────────┬────────────┬─────────┐
│ Function                 │ Version    │ Trigger │
├──────────────────────────┼────────────┼─────────┤
│ getLiveKitToken          │ 1          │ HTTPS   │
│ sendCallNotification     │ 1          │ Event   │
│ cleanupOldCallSignals    │ 1          │ Event   │
└──────────────────────────┴────────────┴─────────┘
```

### Check FCM Token Saved

After opening the app, check logs:

```bash
adb logcat | grep "FCM"
```

**Expected:**
```
FCM: 📱 FCM Token: eyJhbGciOiJSUzI1NiIs...
FCM: ✅ FCM token saved to Firestore
```

### Verify in Firebase Console

1. Open [Firebase Console](https://console.firebase.google.com)
2. Navigate to Firestore Database
3. Go to: `users/{your-user-id}`
4. Check field: `fcmToken` - should have a long string value

---

## Troubleshooting

### Issue: "Cloud Functions require Blaze plan"

**Solution:** Upgrade your Firebase project to Blaze plan (see Prerequisites above)

### Issue: Device doesn't receive call when app is closed

**Checks:**
1. Are Cloud Functions deployed?
   ```bash
   firebase functions:list
   ```

2. Is FCM token saved?
   - Check Firebase Console → Firestore → users/{userId}/fcmToken

3. Check Cloud Function logs:
   ```bash
   firebase functions:log --only sendCallNotification
   ```

4. Check device logs:
   ```bash
   adb logcat | grep -E "FCM|IncomingCall"
   ```

### Issue: Functions deploy fails

**Error:** "Billing account not configured"
- **Solution:** Enable billing in Firebase Console

**Error:** "Permission denied"
- **Solution:** Run `firebase login` and ensure you have admin rights

### Issue: App crashes when receiving call

**Check Android logs:**
```bash
adb logcat | grep AndroidRuntime
```

**Common causes:**
- Missing permissions in manifest (should be added automatically)
- IncomingCallActivity not registered (already registered)

---

## What Happens Behind the Scenes

```
1. User A calls User B
   ↓
2. HomeActivity writes to: users/B/callSignals/xyz
   ↓
3. Cloud Function triggers automatically
   ↓
4. Function reads: users/B/fcmToken
   ↓
5. Function sends FCM push notification to Device B
   ↓
6. Device B receives notification (even if app closed)
   ↓
7. MyFirebaseMessagingService wakes up
   ↓
8. Launches IncomingCallActivity
   ↓
9. User B sees incoming call screen!
```

---

## Cost Estimate

For a typical user:

**Scenario:** 50 calls per day
- **Function invocations:** 50/day × 30 days = 1,500/month
- **Cost:** $0.00 (within 2 million free tier)

**Heavy usage:** 500 calls per day
- **Function invocations:** 500/day × 30 days = 15,000/month
- **Cost:** $0.00 (within 2 million free tier)

**Extreme usage:** 10,000 calls per month
- **Cost:** Still $0.00 (within free tier)

You'd need over **66,000 calls per day** to exceed the free tier!

---

## Quick Reference

### Deploy Commands
```bash
# Deploy everything
firebase deploy

# Deploy only functions
firebase deploy --only functions

# Deploy only Firestore rules
firebase deploy --only firestore:rules
```

### View Logs
```bash
# All function logs
firebase functions:log

# Specific function
firebase functions:log --only sendCallNotification

# Real-time logs (tail)
firebase functions:log --follow
```

### Build Commands
```bash
# Build debug APK
./gradlew assembleDebug

# Build and install
./gradlew installDebug

# Clean build
./gradlew clean assembleDebug
```

---

## Next Steps

After successful deployment and testing:

1. ✅ Test with both devices
2. ✅ Verify background call reception works
3. ✅ Check notification permissions on Android 13+
4. ✅ Monitor Cloud Function logs for first few days
5. ✅ Consider adding custom ringtone (see FCM_PUSH_NOTIFICATIONS.md)

---

## Support Files

- **Detailed FCM docs:** `docs/FCM_PUSH_NOTIFICATIONS.md`
- **Complete fixes summary:** `docs/COMPLETE_FIXES_SUMMARY.md`
- **Call signaling details:** `docs/CALL_SIGNALING_IMPLEMENTATION.md`
- **Battery optimization:** `docs/CALL_STABILITY_IMPROVEMENTS.md`

---

**Status:** ✅ Ready to deploy and test!  
**Deployment time:** ~2 minutes  
**Testing time:** ~5 minutes  
**Total time to working background calls:** ~7 minutes! 🎉
