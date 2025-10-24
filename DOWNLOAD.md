# Download APKs

Latest build: **v21.3** (2025-10-24 20:47 UTC)

## Installation Instructions

1. Click the link for your device below
2. When the file starts downloading in your browser, **right-click the download** and select "Copy Link Address" 
3. Paste that link into a new browser tab on your phone
4. Download and install

## Direct APK Links

### ARM64 (Most phones - Samsung, Pixel, OnePlus, etc.)
**File:** `app-arm64-v8a-debug-2025-10-24-204728.apk` (111 MB)

Raw GitHub link:
```
https://raw.githubusercontent.com/bobbygenerik/3v-repo/copilot/vscode1761074179558/public/apks/app-arm64-v8a-debug-2025-10-24-204728.apk
```

### ARMv7 (Older phones, Fire Tablets)
**File:** `app-armeabi-v7a-debug-2025-10-24-204728.apk` (88 MB)

Raw GitHub link:
```
https://raw.githubusercontent.com/bobbygenerik/3v-repo/copilot/vscode1761074179558/public/apks/app-armeabi-v7a-debug-2025-10-24-204728.apk
```

### x86_64 (Emulators, Chromebooks)
**File:** `app-x86_64-debug-2025-10-24-204728.apk` (149 MB)

Raw GitHub link:
```
https://raw.githubusercontent.com/bobbygenerik/3v-repo/copilot/vscode1761074179558/public/apks/app-x86_64-debug-2025-10-24-204728.apk
```

### x86 (Older emulators)
**File:** `app-x86-debug-2025-10-24-204728.apk` (132 MB)

Raw GitHub link:
```
https://raw.githubusercontent.com/bobbygenerik/3v-repo/copilot/vscode1761074179558/public/apks/app-x86-debug-2025-10-24-204728.apk
```

---

## What's Fixed in v21.3

- ✅ **Fire tablet crash on launch** - Wrapped initialization in try-catch, app won't crash if enhancements fail to load
- ✅ **Guest web calls audio** - Remote audio tracks now attach and play; "Tap to Unmute" button for browser autoplay restrictions
- ✅ **Reduced video startup delay** - Lowered initial capture to 540p with simulcast enabled for faster time-to-first-frame
- ✅ **Mic auto-enable on resume** - Microphone re-enables automatically when returning to call if permission granted
- ✅ **Remote video subscription** - Ensures remote camera feeds are subscribed and render
- ✅ **Offline call blocking** - Calls to offline users (no FCM token) are blocked with a toast message

---

## Need Help?

- Most phones: Use **ARM64**
- Fire Tablet (2020): Use **ARMv7**
- Not sure? Try **ARM64** first, if it doesn't install try **ARMv7**
