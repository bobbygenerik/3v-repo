# Tres3 Video Calling App

A Flutter video calling application with LiveKit WebRTC and Firebase backend.

## Features

### Core Features ✅
- **HD Video Calling** - LiveKit-powered video calls with adaptive bitrate
- **Group Calls** - Multi-participant support with grid layout
- **Real-time Chat** - In-call messaging with Firestore sync
- **Live Reactions** - Animated emoji reactions
- **Guest Links** - Share call links for quick join without sign-up

### Advanced Features ✅
- **E2E Encryption** - Secure peer-to-peer encryption
- **Quality Stats** - Real-time monitoring of call quality
- **Call History** - Track past calls with participants and duration
- **Contact Management** - Add and manage contacts

### Authentication ✅
- Email/Password sign-up and sign-in
- Google Sign-In
- Profile management

## Architecture

- **Flutter App** (Dart + Material3)
- **Firebase Backend** (Cloud Functions, Firestore, FCM, Storage)
- **LiveKit** for WebRTC video/audio infrastructure

## Quick Start

### Prerequisites

- **Flutter SDK** 3.24.5+ (https://flutter.dev/docs/get-started/install)
- **Node.js 20+** (for Cloud Functions)
- **Firebase CLI** (`npm install -g firebase-tools`)
- **LiveKit Cloud Account** (https://cloud.livekit.io/) - Free tier: 10K minutes/month

### 1. Clone and Setup

```bash
git clone <your-repo-url>
cd 3v-repo
```

### 2. Configure Flutter App

```bash
cd tres_flutter

# Run Firebase setup script (auto-configures Firebase)
./setup_firebase.sh

# Or manually:
flutterfire configure

# Edit environment config
# Update lib/config/environment.dart with your LiveKit URL
```

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

### 5. Run Flutter App

```bash
cd tres_flutter

# Get dependencies
flutter pub get

# Run on connected device
flutter run

# Or build APK
flutter build apk --release
```

## Project Structure

```
3v-repo/
├── tres_flutter/                 # Flutter app (main application)
│   ├── lib/
│   │   ├── screens/              # AuthScreen, HomeScreen, CallScreen
│   │   ├── services/             # Core services
│   │   │   ├── livekit_service.dart
│   │   │   ├── auth_service.dart
│   │   │   ├── chat_service.dart
│   │   │   └── ... (more)
│   │   ├── widgets/              # Reusable UI components
│   │   └── config/               # Environment configuration
│   ├── android/                  # Android-specific code
│   ├── ios/                      # iOS-specific code
│   ├── web/                      # Web-specific code
│   └── pubspec.yaml              # Flutter dependencies
├── functions/                    # Firebase Cloud Functions
│   ├── index.js                  # Token generation, notifications
│   └── package.json              # Node dependencies
├── docs/                         # Documentation
└── docs/                         # Documentation
```

## Key Components

### Flutter App Services

**Video/Audio:**
- **LiveKitService**: WebRTC connection, adaptive bitrate, quality optimization
- **CallSignalingService**: Call invitations and room management
- **AudioDeviceService**: Audio device management

**Communication:**
- **ChatService**: Real-time messaging during calls
- **ReactionService**: Live emoji reactions
- **GuestLinkService**: Shareable call links
- **ContactService**: Contact management

**Advanced:**
- **E2EEncryptionService**: Peer-to-peer encryption
- **CallStatsService**: Real-time quality monitoring
- **GridLayoutManager**: Multi-participant layouts
- **NetworkQualityService**: Network monitoring

**Core:**
- **AuthService**: Firebase authentication
- **NotificationService**: Push notifications
- **CallSessionService**: Call session tracking

### Cloud Functions

- **getLiveKitToken**: Generates LiveKit access tokens
- **sendCallNotification**: FCM push notifications
- **generateGuestToken**: Guest link generation
- **cleanupOldCallSignals**: Cleanup expired invitations

## Development

### Running Locally

**Flutter App:**
```bash
cd tres_flutter
flutter run
```

**Cloud Functions (Emulator):**
```bash
cd functions
npm run serve
```

### Testing

```bash
cd tres_flutter

# Analyze code
flutter analyze

# Run unit tests
flutter test

# Run integration tests
flutter test integration_test/
```

### Common Issues

#### 1. Firebase Not Initialized
**Error**: "Firebase not initialized"  
**Fix**: Run `./setup_firebase.sh` or `flutterfire configure`

#### 2. LiveKit Connection Failed
**Error**: "Connection failed"  
**Fix**: Check WebSocket URL format (`wss://` not `https://`) in `lib/config/environment.dart`

#### 3. Functions Timeout
**Error**: Cloud Functions timeout  
**Fix**: Check `firebase functions:log` and verify `.env` is deployed

#### 4. Permission Denied
**Error**: Camera/microphone access denied  
**Fix**: Grant permissions in device settings

## Documentation

**Flutter App Documentation:**
- `tres_flutter/QUICKSTART.md` - 15-minute setup guide
- `tres_flutter/FIREBASE_SETUP_GUIDE.md` - Complete Firebase configuration
- `tres_flutter/INTEGRATION_CHECKLIST.md` - Testing & deployment guide
- `tres_flutter/FEATURE_STATUS.md` - Feature implementation status

**Root Documentation:**
- `VIDEO_CALL_QUALITY_AUDIT_REPORT.md` - Video quality optimization
- `OPTIMIZATION_AUDIT_REPORT.md` - Performance improvements
- `docs/` - Legacy Android documentation

## Technology Stack

- **Framework**: Flutter 3.24.5
- **Language**: Dart 3.9.2
- **UI**: Material3 + Custom widgets
- **Backend**: Firebase (Firestore, Functions, FCM, Storage)
- **Video**: LiveKit Client 2.6.1 (WebRTC)
- **State**: Provider 6.1.2
- **Platforms**: Android, iOS, Web

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

**Last Updated**: January 27, 2026  
**Version**: 2.0 (Flutter)  
**Status**: Production-ready
