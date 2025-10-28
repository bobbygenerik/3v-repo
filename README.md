# Três3 - Video Calling App (LiveKit + Firebase)

A modern Android video calling app using Kotlin, View Binding, Firebase Auth, Firestore, and LiveKit for high-quality video calls. Features real-time contact management, push notifications, and professional call interface.

## Features
- 1:1 and group video calling using LiveKit SDK
- Firebase Authentication (Email/Password)
- Firestore-based contact management
- FCM push notifications for incoming calls
- Professional call UI with PIP mode and controls
- Real-time participant management
- Intent integration for call initiation

## Project Setup

### Prerequisites
- Android Studio or command-line tools
- Java 17 (JDK)
- Android SDK with platform-tools, platforms;android-35, build-tools;35.0.0

### Firebase Setup
1. Create a Firebase project at https://console.firebase.google.com/
2. Enable Authentication with Email/Password provider
3. Enable Firestore Database
4. Enable Firebase Cloud Messaging
5. Download `google-services.json` and place it in `app/` directory
6. Update the package name in `google-services.json` to `com.example.tres3`

### LiveKit Setup
1. Create a LiveKit Cloud account at https://cloud.livekit.io/
2. Create a new project
3. Get your API Key and API Secret from the project settings
4. Update `app/src/main/java/com/example/tres3/livekit/LiveKitConfig.kt`:
   ```kotlin
   const val LIVEKIT_URL = "wss://your-project.livekit.cloud"
   const val API_KEY = "your-api-key"
   const val API_SECRET = "your-api-secret"
   ```

### Build Instructions

**Debug build:**
```bash
./gradlew assembleDebug
```

**Release build:**
```bash
./gradlew assembleRelease
```

APK output locations:
- Debug: `app/build/outputs/apk/debug/app-debug.apk`
- Release: `app/build/outputs/apk/release/app-release-unsigned.apk`

	- Debug build:

	```bash
	./gradlew assembleDebug
	```

	- Release build (unsigned by default unless you configure signing):

	```bash
	./gradlew assembleRelease
	```

	APK output locations:
	- Debug: `app/build/outputs/apk/debug/app-debug.apk`
	- Release: `app/build/outputs/apk/release/app-release-unsigned.apk`

3) Install/run on a device

	**Codespaces cannot run the Android emulator or the app.**
	To test or use the app, download the APK to your local machine and install it on a physical Android device or emulator.

## Dependencies (Gradle)
- LiveKit Android SDK 2.20.3
- Firebase BOM: Auth, Firestore, Cloud Messaging, Analytics, Crashlytics
- Glide 4.16.0 for image loading
- Material Design 3 components
- View Binding for UI

## Architecture
- **MainActivity**: App entry point with authentication routing
- **SignInActivity**: Firebase email/password authentication
- **CreateAccountActivity**: User registration with Firestore profile creation
- **DashboardActivity**: Main screen with contacts list and call initiation
- **InCallActivity**: LiveKit-powered video calling interface
- **ProfileActivity**: User profile management
- **LiveKitConfig**: JWT token generation and server configuration

## Call Flow
1. User selects contact from dashboard
2. App generates unique room name and JWT token
3. LiveKit room connection established
4. Local camera/microphone activated
5. Remote participant video streams displayed
6. Call controls (mute, camera switch, end call) available

## Permissions Required
- `CAMERA`: Video capture
- `RECORD_AUDIO`: Audio capture
- `INTERNET`: Network communication
- `ACCESS_NETWORK_STATE`: Network state monitoring

## Notes
- For production deployment, consider server-side token generation for enhanced security
- LiveKit Cloud provides global infrastructure with automatic scaling
- Push notifications require FCM configuration for background call alerts

