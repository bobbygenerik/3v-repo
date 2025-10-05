# P2P Video (Compose + Firebase + native WebRTC)

An MVVM-structured Android app using Kotlin, Jetpack Compose (Material 3), Firebase Auth, Firestore signaling, and native WebRTC for 1:1 video calls. Includes intent integration for call initiation (e.g., from Google Messages) via `tel:` and custom deep links.

## Features
- 1:1 video calling using native WebRTC (UNIFIED_PLAN)
- 1080p target capture with relay-aware max bitrate adaptation
- Compose M3 UI (minimal, dynamic color if available)
- Firebase Auth (phone-only sign-in)
- Firestore-based signaling (offer/answer + ICE)
- Intent filters for:
	- tel: scheme (e.g., tel:+15551234567)
	- custom deep link: `p2pvideo://call/<id or number>`
	- content URI: `content://com.example.threevchat/call/<id or number>`
- MVVM layering (ViewModel, Repository)

## Project setup (Codespaces/CLI)

This project is intended to be **built** inside GitHub Codespaces (no Android Studio required).

**You cannot run or test the app in Codespaces.**
After building, download the APK and install it on a physical Android device or emulator.

Prerequisites inside the Codespaces container:
- Java 17 (JDK) available on PATH
- Android SDK command-line tools installed with the following packages:
  - platform-tools
  - platforms;android-35
  - build-tools;35.0.0

You can use the helper script below to install and configure the Android SDK locally in the container under `~/android-sdk`.

1) One-time Android SDK setup in Codespaces

	- Put your Firebase config at `app/google-services.json` (download from Firebase Console). Enable Email/Password and Phone providers in Firebase Auth.
	- Run the setup script to install the Android SDK CLI and required packages:

	```bash
	bash scripts/setup-android-sdk.sh
	```

	The script will:
	- Download Android command-line tools
	- Install platform-tools, Android 35 platform, and Build Tools 35.0.0
	- Accept Android SDK licenses
	- Append environment variables to your shell profile

	After the script finishes, either start a new shell or `source ~/.bashrc` to load environment variables.

2) Build the app (APK)

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
- Compose BOM, Material3 1.3.0
- Firebase BOM 33.3.0, Auth, Analytics, Firestore
- Native WebRTC: `io.github.webrtc-sdk:android:137.7151.04`
- Play Services Auth, Auth API Phone

## Intent integration
- tel: `tel:+15551234567` — parsed in `MainActivity` -> `MainViewModel.handleIncomingIntent`
- Custom deep link: `p2pvideo://call/<id_or_number>`
- Content URI: `content://com.example.threevchat/call/<id_or_number>`

For now, initiating a call creates a Firestore session and launches a native `CallActivity` as the caller. Joining via a shared session link is planned and will pass `role=callee` with an existing `sessionId`.

## Notes
- For production, add proper permission flows, error handling, and DI.
- To avoid reCAPTCHA Enterprise billing for phone auth in development, a debug-only bypass is enabled in `P2PApp`. Do not enable this in release builds.

