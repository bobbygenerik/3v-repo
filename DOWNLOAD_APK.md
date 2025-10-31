# 📱 How to Get the Tres3 APK

## Option 1: Download from GitHub Actions (Recommended - Fastest) ⚡

### Trigger Automated Build:

1. **Go to GitHub Actions**:
   ```
   https://github.com/bobbygenerik/3v-repo/actions
   ```

2. **Click "Android Release (Signed APK/AAB)"** workflow

3. **Click "Run workflow"** button (top right)

4. **Wait 5-10 minutes** for build to complete

5. **Download APK** from the artifacts section at the bottom

**Direct workflow trigger URL:**
```
https://github.com/bobbygenerik/3v-repo/actions/workflows/android-release.yml
```

---

## Option 2: Build Locally (Full Control) 🔨

### Prerequisites:
- Android Studio or Android SDK
- JDK 17
- Git

### Steps:

```bash
# 1. Clone repo (if not already)
git clone https://github.com/bobbygenerik/3v-repo.git
cd 3v-repo

# 2. Setup configuration
cp local.properties.example local.properties
# Edit local.properties with:
# - sdk.dir=/path/to/your/Android/Sdk
# - livekit.url=wss://your-project.livekit.cloud
# - livekit.api.key=YOUR_KEY
# - livekit.api.secret=YOUR_SECRET

# 3. Build APK
./build-release.sh

# 4. APK Location:
# app/build/outputs/apk/debug/app-debug.apk
```

### Install on Phone:
```bash
adb install app/build/outputs/apk/debug/app-debug.apk
```

Or copy to your phone and install directly.

---

## Option 3: Quick Local Build (No Config Needed) 🚀

If you just want to test the UI without LiveKit features:

```bash
cd /path/to/3v-repo

# Create minimal config (empty LiveKit creds)
echo 'sdk.dir=/path/to/Android/Sdk' > local.properties
echo 'livekit.url=' >> local.properties
echo 'livekit.api.key=' >> local.properties
echo 'livekit.api.secret=' >> local.properties

# Build
./gradlew :app:assembleDebug --no-daemon

# APK location:
# app/build/outputs/apk/debug/app-debug.apk
```

⚠️ **Note**: Without LiveKit credentials, video calls won't work but you can test the UI.

---

## Option 4: Use Pre-built APK from Releases (If Available)

Check if there are releases with pre-built APKs:

```
https://github.com/bobbygenerik/3v-repo/releases
```

---

## Current Status

✅ **Build system configured** - Ready to build  
✅ **GitHub Actions workflow** - Automated builds available  
✅ **Build script created** - `build-release.sh`  
⚠️ **Android SDK required** - Not available in cloud dev environment  

---

## Quick Reference

| Method | Speed | Requires | Best For |
|--------|-------|----------|----------|
| **GitHub Actions** | ⚡ Fastest | GitHub account | Quick downloads |
| **Local Build** | 🔨 Medium | Android SDK | Development |
| **Releases Page** | 📦 Instant | Nothing | Stable versions |

---

## Need Help?

1. **Build fails?** Check `README.md` for prerequisites
2. **Can't install APK?** Enable "Unknown sources" on your phone
3. **App crashes?** Ensure `google-services.json` is in `app/` directory

---

**Recommended:** Use **GitHub Actions** (Option 1) for the fastest way to get a working APK!
