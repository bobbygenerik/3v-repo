# P2P Video (Jitsi + Compose + Firebase)

A minimal, MVVM-structured Android app using Kotlin, Jetpack Compose (Material 3), Firebase Auth, and Jitsi Meet SDK for peer-to-peer video calls. Includes Intent integration for call initiation (e.g., from Google Messages) via custom deep links or content URIs.

## Features
- Video calling via Jitsi Meet SDK
- Compose M3 UI (minimal, dynamic color if available)
- Firebase Auth for username (email+password) and phone sign-in
- Intent filters for deep links and content URIs to start calls
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
- Firebase BOM 33.3.0, Auth, Analytics
- Jitsi Meet SDK 8.6.0
- Play Services Auth, Auth API Phone

## Intent integration
- Custom deep link: `p2pvideo://call/<username_or_phone>`
- Content URI: `content://com.example.p2pvideojitsi/call/<username_or_phone>`
- Both handled by `MainActivity` -> `MainViewModel.handleIncomingIntent` -> `JitsiRepository.parseCallIntent`.

## Notes
- Jitsi P2P is automatically negotiated when 2 participants and supported.
- For production, add proper permission flows, error handling, and DI.

