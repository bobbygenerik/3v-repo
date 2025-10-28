# Flutter Migration Guide

## Decision: Migrating to Flutter for Cross-Platform Support

**Date:** October 28, 2025  
**Reason:** Enable iOS development from Codespaces (no Mac required)  
**Status:** Android app (10/34 tasks complete) → Flutter migration started

---

## Why Flutter?

### The Problem:
- ✅ Android app 29% complete with excellent features
- ❌ No Mac access = Cannot build native iOS apps
- ❌ Cannot use Swift/Xcode from Codespaces
- 🎯 **Goal:** Cross-platform Android ↔ iOS video calling

### The Solution:
**Flutter + Codemagic CI/CD**
- ✅ Develop iOS apps from Linux/Codespaces
- ✅ Single Dart codebase for Android + iOS
- ✅ LiveKit has official Flutter SDK
- ✅ Codemagic compiles iOS builds in cloud
- ✅ Test on real devices via cloud services

---

## Migration Strategy

### Phase 1: Foundation (Week 1) - **IN PROGRESS**
- [x] Install Flutter SDK in Codespaces
- [x] Create Flutter project (`tres_flutter/`)
- [x] Add dependencies (LiveKit, Firebase, Camera)
- [ ] Set up project structure (screens/, services/, models/, widgets/)
- [ ] Configure Firebase for Flutter
- [ ] Create AuthService (Firebase Auth)
- [ ] Build SignInScreen (phone/email auth)

### Phase 2: Core Features (Week 2)
- [ ] Port LiveKitManager → LiveKitService
- [ ] Build HomeScreen (contact list)
- [ ] Build CallScreen (video rendering)
- [ ] Implement InCallControls widget
- [ ] Port Firebase signaling logic

### Phase 3: Feature Porting (Weeks 3-4)
Port completed Android features to Flutter:

**From Android Tasks 1-10:**
1. User Presence System → Firebase Realtime Database + StreamBuilder
2. Audio-only Mode → LiveKit track control
3. Mute Others → LiveKit metadata
4. Contact Favorites → Local storage (shared_preferences)
5. Vibration Patterns → vibration package
6. Call Quality Dashboard → LiveKit stats API
7. Noise Suppression → LiveKit audio settings
8. WhisperAI Captions → http package + OpenAI API
9. Low-light Enhancement → Platform channels to native (if needed)
10. Face Auto-Framing → tflite_flutter or platform channels

### Phase 4: iOS Enablement (Week 5)
- [ ] Create Codemagic account
- [ ] Configure `codemagic.yaml`
- [ ] Set up iOS provisioning profiles
- [ ] First iOS build in cloud
- [ ] Test on physical iPhone

### Phase 5: Advanced Features (Weeks 6+)
- [ ] Continue porting remaining 24 Android tasks
- [ ] Platform-specific optimizations
- [ ] App Store submission

---

## Current Setup

### Installed:
```bash
Flutter 3.35.7 (stable channel)
Dart 3.9.2
Location: /workspaces/flutter/bin
```

### Dependencies Added:
```yaml
# Video Calling
livekit_client: ^2.3.5

# Firebase
firebase_core: ^3.6.0
firebase_auth: ^5.3.1
cloud_firestore: ^5.4.4
firebase_messaging: ^15.1.3

# State Management
provider: ^6.1.2

# Utilities
permission_handler: ^11.3.1
camera: ^0.11.0+2
wakelock_plus: ^1.2.8
intl: ^0.20.1
```

---

## Project Structure (Planned)

```
tres_flutter/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── screens/
│   │   ├── auth_screen.dart      # Phone/email sign in
│   │   ├── home_screen.dart      # Contact list
│   │   ├── call_screen.dart      # Video call UI
│   │   └── settings_screen.dart  # App settings
│   ├── services/
│   │   ├── auth_service.dart     # Firebase Auth wrapper
│   │   ├── livekit_service.dart  # LiveKit room management
│   │   ├── signaling_service.dart # Firestore signaling
│   │   └── presence_service.dart  # User presence tracking
│   ├── models/
│   │   ├── user.dart             # User data model
│   │   ├── call_session.dart     # Call session model
│   │   └── contact.dart          # Contact model
│   ├── widgets/
│   │   ├── in_call_controls.dart # Call control buttons
│   │   ├── participant_tile.dart # Video tile widget
│   │   ├── captions_overlay.dart # Live captions UI
│   │   └── quality_indicator.dart # Network quality
│   └── utils/
│       ├── permissions.dart      # Permission handling
│       └── constants.dart        # App constants
├── android/                      # Android-specific config
├── ios/                          # iOS-specific config
├── codemagic.yaml               # CI/CD configuration
└── pubspec.yaml                 # Dependencies
```

---

## Key Differences: Android (Kotlin) vs Flutter (Dart)

### State Management
**Android (Kotlin):**
```kotlin
var isMuted by remember { mutableStateOf(false) }
```

**Flutter (Dart):**
```dart
bool isMuted = false;
setState(() { isMuted = !isMuted; });
```

### LiveKit Integration
**Android (Kotlin):**
```kotlin
val room = Room(context)
room.connect(url, token)
```

**Flutter (Dart):**
```dart
final room = Room();
await room.connect(url, token);
```

### Firebase Auth
**Android (Kotlin):**
```kotlin
FirebaseAuth.getInstance().currentUser
```

**Flutter (Dart):**
```dart
FirebaseAuth.instance.currentUser
```

---

## Feature Mapping: Android → Flutter

| Android Feature | Flutter Equivalent | Difficulty |
|----------------|-------------------|------------|
| Jetpack Compose | Flutter Widgets | ⭐ Easy (very similar) |
| LiveKitManager | livekit_client package | ⭐⭐ Medium |
| ML Kit Face Detection | google_mlkit_face_detection | ⭐⭐ Medium |
| OpenCV Processing | opencv_dart or platform channels | ⭐⭐⭐ Hard |
| MediaPipe Hands | mediapipe_dart or platform channels | ⭐⭐⭐ Hard |
| CameraX | camera package | ⭐⭐ Medium |
| Vibration | vibration package | ⭐ Easy |
| OkHttp | http or dio package | ⭐ Easy |

---

## Codemagic Setup (For iOS Builds)

### codemagic.yaml (To be created):
```yaml
workflows:
  ios-workflow:
    name: iOS Production Build
    instance_type: mac_mini_m1
    max_build_duration: 60
    environment:
      xcode: latest
      flutter: stable
      vars:
        BUNDLE_ID: "com.example.tres3.tresFlutter"
    scripts:
      - name: Get Flutter packages
        script: flutter pub get
      - name: Build iOS
        script: |
          flutter build ios --release \
            --no-codesign \
            --build-name=1.0.$BUILD_NUMBER
    artifacts:
      - build/ios/ipa/*.ipa
    publishing:
      app_store_connect:
        # Configure with App Store credentials
```

### Benefits:
- ✅ No Mac needed locally
- ✅ Automated builds on git push
- ✅ Test distribution via TestFlight
- ✅ App Store submission from cloud

---

## Next Steps (Immediate)

### 1. Set up Firebase Configuration
```bash
# Download google-services.json from Firebase Console
# Place in: tres_flutter/android/app/

# Download GoogleService-Info.plist from Firebase Console  
# Place in: tres_flutter/ios/Runner/
```

### 2. Create Project Structure
```bash
cd tres_flutter/lib
mkdir screens services models widgets utils
```

### 3. Implement AuthService
- Firebase Auth with phone number
- Email/password fallback
- Stream-based auth state

### 4. Build SignInScreen
- Phone number input with country code
- SMS verification flow
- Loading states

### 5. Test on Android First
```bash
flutter run
# Then gradually add iOS testing via Codemagic
```

---

## Timeline Estimate

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| Foundation | 1 week | Auth + basic UI |
| Core Features | 1 week | LiveKit calling works |
| Feature Porting | 2 weeks | 10 Android features ported |
| iOS Setup | 1 week | First iOS build |
| Polish | 2 weeks | Feature parity + testing |
| **Total** | **7 weeks** | **Cross-platform app** |

---

## Rollback Plan (If Needed)

If Flutter migration hits major blockers:
1. Android app code preserved in `/app` directory
2. Can continue Android-only development
3. Flutter code lives in `/tres_flutter` (isolated)

But given no Mac access, **Flutter is the only path to iOS**.

---

## Resources

- [LiveKit Flutter SDK Docs](https://docs.livekit.io/client-sdk-flutter/)
- [Firebase Flutter Setup](https://firebase.google.com/docs/flutter/setup)
- [Codemagic Flutter Guide](https://docs.codemagic.io/flutter-quick-start/)
- [Flutter Video Call Example](https://github.com/livekit/client-sdk-flutter/tree/main/example)

---

## Questions & Decisions

**Q: What happens to the Android code?**  
A: Preserved in `/app`. Can reference during porting. Not deleted.

**Q: Will video quality be the same?**  
A: Yes. LiveKit handles video/audio server-side. Client SDK doesn't affect quality.

**Q: Can we still use ML Kit and OpenCV?**  
A: Yes via Flutter plugins or platform channels (slightly more complex).

**Q: How do we test iOS without a Mac?**  
A: Codemagic builds iOS, distributes via TestFlight, test on physical iPhone.

**Q: Will cross-platform calling work?**  
A: Yes! LiveKit server handles Android ↔ iOS ↔ Web seamlessly.

---

**Migration initiated:** October 28, 2025  
**Current status:** Phase 1 in progress (Flutter installed, project created, dependencies added)  
**Next milestone:** Complete AuthService + SignInScreen
