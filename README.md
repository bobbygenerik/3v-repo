# Tres3 Video Calling App

A production-ready Android video calling application with LiveKit integration, Firebase Cloud Functions, and native Android ConnectionService UI.

## Features

✅ **1-to-1 Video Calls** with LiveKit WebRTC  
✅ **Native Android UI** via ConnectionService (system call screens)  
✅ **Background Call Reception** with FCM push notifications  
✅ **Guest Invite Links** for web users (no app required)  
✅ **Call Signaling** via Firestore real-time database  
✅ **Cloud Functions** for token generation and notifications  
✅ **Advanced Camera Controls** (switch, filters, effects)  
✅ **Professional UI** with Jetpack Compose Material3

## Architecture

- **Android App** (Kotlin + Jetpack Compose)
- **Firebase Backend** (Cloud Functions, Firestore, FCM)
- **LiveKit** for WebRTC video/audio infrastructure
- **ConnectionService** for native Android call UI

## Quick Start

### Prerequisites

- **JDK 17** (required for Android Gradle Plugin 8.7.3)
- **Android SDK** (API 24-35)
- **Node.js 20+** (for Cloud Functions)
- **Firebase CLI** (`npm install -g firebase-tools`)
- **LiveKit Cloud Account** (https://cloud.livekit.io/)

### 1. Clone and Setup

```bash
git clone <your-repo-url>
cd 3v-repo
```

### 2. Configure Android App

```bash
# Copy and edit local.properties
cp local.properties.example local.properties

# Edit local.properties with:
# - Your Android SDK path
# - LiveKit credentials from https://cloud.livekit.io/
```

**Important**: `local.properties` is gitignored. Never commit credentials!

### 3. Configure Cloud Functions

```bash
cd functions

# Copy and edit .env
cp .env.example .env

# Edit .env with your LiveKit credentials

# Install dependencies
npm install
```

### 4. Deploy Cloud Functions

```bash
# Login to Firebase
firebase login

# Select your Firebase project
firebase use <your-project-id>

# Deploy functions
firebase deploy --only functions
```

Or set config directly:

```bash
firebase functions:config:set \
  livekit.key="YOUR_KEY" \
  livekit.secret="YOUR_SECRET" \
  livekit.url="wss://your-project.livekit.cloud"
```

### 5. Build Android App

```bash
# Return to project root
cd ..

# Build debug APK
./gradlew :app:assembleDebug

# Install on device/emulator
./gradlew :app:installDebug
```

## Project Structure

```
3v-repo/
├── app/                          # Android app source
│   ├── src/main/java/com/example/tres3/
│   │   ├── HomeActivity.kt       # Main screen, contacts list
│   │   ├── InCallActivity.kt     # Active call UI
│   │   ├── IncomingCallActivity.kt # Incoming call handler
│   │   ├── Tres3ConnectionService.kt # Native call UI integration
│   │   ├── MyFirebaseMessagingService.kt # FCM push handler
│   │   ├── CallSignalingManager.kt # Firestore signaling
│   │   └── LiveKitManager.kt     # LiveKit connection manager
│   └── build.gradle              # App dependencies
├── functions/                    # Firebase Cloud Functions
│   ├── index.js                  # Main functions (token gen, notifications)
│   └── package.json              # Node dependencies
├── docs/                         # Comprehensive documentation
├── build.gradle                  # Root build config
└── local.properties.example      # Template for local config
```

## Key Components

### Android App

- **HomeActivity**: Contact list, call initiation, FCM token registration
- **InCallActivity**: Active call UI with video rendering and controls
- **IncomingCallActivity**: Full-screen incoming call handler
- **Tres3ConnectionService**: Native Android call UI via Telecom framework
- **MyFirebaseMessagingService**: FCM push notification receiver
- **CallSignalingManager**: Firestore-based call invitation signaling
- **LiveKitManager**: LiveKit room connection and media management

### Cloud Functions

- **getLiveKitToken**: Generates LiveKit access tokens for authenticated users
- **sendCallNotification**: Sends FCM push when call invitation is created
- **generateGuestToken**: Creates shareable links for web guests
- **joinGuest**: Handles guest invitation claims and redirects
- **cleanupOldCallSignals**: Periodic cleanup of expired invitations

## Development

### Running Locally

**Android App:**
```bash
./gradlew :app:assembleDebug
./gradlew :app:installDebug
```

**Cloud Functions (Emulator):**
```bash
cd functions
npm run serve
```

### Testing

```bash
# Unit tests
./gradlew test

# Instrumentation tests
./gradlew connectedAndroidTest
```

### Common Issues

#### 1. Missing LiveKit Credentials
**Error**: "LiveKit credentials not configured"  
**Fix**: Ensure `local.properties` (app) and `.env` (functions) have valid LiveKit credentials

#### 2. Node Version Mismatch
**Error**: Firebase Functions deployment fails  
**Fix**: Use Node.js 20 (run `nvm use 20` or install from nodejs.org)

#### 3. Java Version Issues
**Error**: Gradle build fails with version errors  
**Fix**: Use JDK 17 (`export JAVA_HOME=/path/to/jdk-17`)

#### 4. FCM Token Not Registered
**Error**: Notifications not received  
**Fix**: Ensure `google-services.json` is in `app/` directory and app has run at least once

## Documentation

Detailed documentation is available in the `docs/` directory:

- **CONNECTIONSERVICE_INTEGRATION.md**: Native Android UI implementation
- **FCM_PUSH_NOTIFICATIONS.md**: Background notification setup
- **CALL_SIGNALING_IMPLEMENTATION.md**: Firestore signaling architecture
- **NOTIFICATION_TROUBLESHOOTING.md**: FCM debugging guide
- **COMPLETE_FIXES_SUMMARY.md**: Recent fixes and improvements

## Technology Stack

- **Language**: Kotlin
- **UI**: Jetpack Compose + Material3
- **Backend**: Firebase (Firestore, Functions, FCM)
- **Video**: LiveKit WebRTC
- **Build**: Gradle 8.9, AGP 8.7.3
- **Min SDK**: 24 (Android 7.0)
- **Target SDK**: 35 (Android 15)

## Contributing

1. Create a feature branch
2. Make your changes
3. Test thoroughly
4. Submit a pull request

## License

[Your License Here]

## Support

For issues or questions, check the documentation in `docs/` or open an issue.

---

**Last Updated**: October 30, 2025  
**Version**: 1.4 (call-fixes)
