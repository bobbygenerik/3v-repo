# Firebase Setup Guide for Flutter App

## Prerequisites
- Node.js and npm installed
- Flutter SDK installed
- Firebase CLI installed: `npm install -g firebase-tools`
- FlutterFire CLI: `dart pub global activate flutterfire_cli`

---

## Step 1: Create New Firebase Project

1. **Go to Firebase Console**: https://console.firebase.google.com/
2. **Create a new project**:
   - Click "Add project"
   - Project name: `3v-video-calls` (or your preferred name)
   - Enable Google Analytics (recommended)
   - Click "Create project"

---

## Step 2: Enable Required Services

### 2.1 Authentication
1. In Firebase Console, go to **Build > Authentication**
2. Click "Get started"
3. Enable sign-in methods:
   - ✅ Email/Password
   - ✅ Google (recommended)
   - ✅ Anonymous (for guest calls)
4. Click "Save"

### 2.2 Firestore Database
1. Go to **Build > Firestore Database**
2. Click "Create database"
3. Choose **Production mode** (we have security rules)
4. Select location (choose closest to your users)
5. Click "Enable"

### 2.3 Storage
1. Go to **Build > Storage**
2. Click "Get started"
3. Choose **Production mode**
4. Use same location as Firestore
5. Click "Done"

### 2.4 Cloud Messaging (FCM)
1. Go to **Build > Cloud Messaging**
2. Click "Get started"
3. Note: Configuration will be done automatically by FlutterFire

---

## Step 3: Configure Flutter App

### 3.1 Install FlutterFire CLI (if not already installed)
```bash
dart pub global activate flutterfire_cli
```

### 3.2 Login to Firebase
```bash
firebase login
```

### 3.3 Run FlutterFire Configure
```bash
# Make sure you're in the Flutter project directory
cd /repos/tres3/3v-repo/tres_flutter

# Configure Firebase for all platforms
flutterfire configure \
  --project=YOUR_PROJECT_ID \
  --platforms=android,ios,web \
  --out=lib/firebase_options.dart \
  --android-package-name=com.threeveesocial.tresvideo \
  --ios-bundle-id=com.threeveesocial.tresvideo
```

**This command will:**
- Create `lib/firebase_options.dart`
- Download `android/app/google-services.json`
- Download `ios/Runner/GoogleService-Info.plist`
- Configure all necessary Firebase SDKs

---

## Step 4: Deploy Firestore Security Rules

```bash
cd /repos/tres3/3v-repo

# Deploy security rules
firebase deploy --only firestore:rules

# Deploy storage rules (if you have them)
firebase deploy --only storage
```

---

## Step 5: Set Up Firebase Functions

### 5.1 Configure Functions
```bash
cd /repos/tres3/3v-repo/functions

# Install dependencies
npm install

# Create .env file with your credentials
cp .env.example .env
```

### 5.2 Edit `.env` file:
```bash
# Firebase Admin
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_CLIENT_EMAIL=your-service-account-email
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"

# LiveKit Configuration
LIVEKIT_API_KEY=your-livekit-api-key
LIVEKIT_API_SECRET=your-livekit-api-secret
LIVEKIT_URL=wss://your-livekit-server.com
```

### 5.3 Get Firebase Service Account Key
1. Go to **Project Settings > Service accounts**
2. Click "Generate new private key"
3. Save the JSON file
4. Copy values to `.env` file

### 5.4 Deploy Functions
```bash
firebase deploy --only functions
```

---

## Step 6: Set Up LiveKit

### Option A: LiveKit Cloud (Recommended - Easy)
1. Go to https://cloud.livekit.io/
2. Create an account
3. Create a new project
4. Copy **API Key**, **API Secret**, and **WebSocket URL**
5. Add to `functions/.env`

### Option B: Self-Hosted LiveKit
```bash
# Using Docker
docker run -d \
  --name livekit \
  -p 7880:7880 \
  -p 7881:7881 \
  -p 7882:7882/udp \
  -v $PWD/livekit-config.yaml:/etc/livekit.yaml \
  livekit/livekit-server \
  --config /etc/livekit.yaml
```

**Create `livekit-config.yaml`:**
```yaml
port: 7880
rtc:
  port_range_start: 7882
  port_range_end: 7882
  use_external_ip: true

keys:
  your-api-key: your-api-secret
```

---

## Step 7: Update Flutter Environment Configuration

Create `lib/config/environment.dart`:
```dart
class Environment {
  // Firebase (auto-configured by FlutterFire)
  static const String appName = '3V Video Calls';
  
  // LiveKit
  static const String liveKitUrl = 'wss://your-livekit-server.com';
  
  // Backend API
  static const String functionsBaseUrl = 
      'https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net';
  
  // Feature flags
  static const bool enableMLFeatures = true;
  static const bool enableE2EEncryption = true;
  static const bool enableCloudRecording = true;
}
```

---

## Step 8: Verify Configuration

### 8.1 Check Files Exist
```bash
# Should exist after flutterfire configure
ls -la lib/firebase_options.dart
ls -la android/app/google-services.json
ls -la ios/Runner/GoogleService-Info.plist
```

### 8.2 Test Firebase Connection
```bash
cd /repos/tres3/3v-repo/tres_flutter
flutter run

# In the app, try:
# 1. Sign up with email/password
# 2. Check Firestore console for user document
# 3. Try uploading a profile picture (tests Storage)
```

---

## Step 9: Configure Platform Permissions

### Android (`android/app/src/main/AndroidManifest.xml`)
Already configured, but verify these permissions exist:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
```

### iOS (`ios/Runner/Info.plist`)
Add camera/microphone descriptions:
```xml
<key>NSCameraUsageDescription</key>
<string>We need camera access for video calls</string>
<key>NSMicrophoneUsageDescription</key>
<string>We need microphone access for video calls</string>
```

---

## Step 10: Test Everything

### Test Checklist:
- [ ] Firebase Authentication (sign up, sign in)
- [ ] Firestore (user profiles, call history)
- [ ] Storage (profile pictures, recordings)
- [ ] LiveKit (video call connection)
- [ ] FCM (push notifications)
- [ ] ML Features (face detection, filters)
- [ ] Recording (upload to Storage)
- [ ] Encryption (toggle on/off)
- [ ] Screen sharing (Android/iOS permissions)

---

## Troubleshooting

### "FlutterFire configuration not found"
```bash
# Re-run configure
flutterfire configure
```

### "LiveKit connection failed"
- Check WebSocket URL format: `wss://` not `https://`
- Verify API key/secret are correct
- Test with LiveKit playground: https://meet.livekit.io/

### "Firebase functions not working"
```bash
# Check logs
firebase functions:log

# Verify deployment
firebase functions:list
```

### "ML Kit not working on emulator"
- ML features require **real device** with camera
- Emulator has limited ML Kit support

---

## Quick Start Commands Summary

```bash
# 1. Firebase login
firebase login

# 2. FlutterFire configure
cd /repos/tres3/3v-repo/tres_flutter
flutterfire configure

# 3. Deploy Firestore rules
cd /repos/tres3/3v-repo
firebase deploy --only firestore:rules

# 4. Deploy functions
cd /repos/tres3/3v-repo/functions
npm install
# Edit .env with your credentials
firebase deploy --only functions

# 5. Run Flutter app
cd /repos/tres3/3v-repo/tres_flutter
flutter run
```

---

## Production Checklist

Before launching:
- [ ] Set up proper Firestore security rules
- [ ] Configure Firebase Authentication email templates
- [ ] Set up Firebase App Check for security
- [ ] Configure proper CORS for Storage
- [ ] Set up Firebase Analytics
- [ ] Configure crash reporting
- [ ] Set up proper logging/monitoring
- [ ] Test on multiple devices (iOS + Android)
- [ ] Load test with multiple concurrent users
- [ ] Set up CI/CD pipeline

---

## Cost Estimation

**Firebase (Spark Plan - FREE tier includes):**
- 10K document writes/day
- 50K document reads/day
- 1GB storage
- 10GB/month transfer

**LiveKit Cloud (Free tier):**
- 10,000 participant minutes/month

**Upgrade when needed:**
- Firebase Blaze: Pay-as-you-go
- LiveKit Cloud: Starts at $99/month

---

## Support Resources

- **Firebase Docs**: https://firebase.google.com/docs/flutter/setup
- **FlutterFire**: https://firebase.flutter.dev/
- **LiveKit Flutter SDK**: https://docs.livekit.io/client-sdk-flutter/
- **Your Functions Endpoint**: `https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net`

---

**Status**: Ready to configure! Start with Step 1 in Firebase Console.
