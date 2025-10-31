# 🚀 Quick Start - New Firebase Project Setup

## ⏱️ 15-Minute Setup (Fastest Path)

### Step 1: Create Firebase Project (2 minutes)
```
1. Go to https://console.firebase.google.com/
2. Click "Add project"
3. Enter project name: "3v-video-calls"
4. Enable Google Analytics (optional)
5. Click "Create project"
```

### Step 2: Enable Firebase Services (3 minutes)
```
In Firebase Console, enable:
☑️ Authentication → Email/Password + Google + Anonymous
☑️ Firestore Database → Production mode → Choose location
☑️ Storage → Production mode → Same location
☑️ Cloud Messaging → Automatically enabled
```

### Step 3: Run Automated Setup Script (5 minutes)
```bash
cd /repos/tres3/3v-repo/tres_flutter
./setup_firebase.sh
```

**The script will:**
- ✅ Check all prerequisites (Flutter, Firebase CLI, FlutterFire CLI)
- ✅ Login to Firebase
- ✅ Configure FlutterFire (creates all config files)
- ✅ Download google-services.json and GoogleService-Info.plist
- ✅ Update environment.dart with your project ID
- ✅ Optionally deploy Firestore rules
- ✅ Optionally set up Firebase Functions

### Step 4: Set Up LiveKit (3 minutes)

**Option A - LiveKit Cloud (Recommended):**
```
1. Go to https://cloud.livekit.io/
2. Sign up (free tier: 10K minutes/month)
3. Create a project
4. Copy: API Key, API Secret, WebSocket URL
```

**Option B - Self-Hosted (Advanced):**
```bash
docker run -d -p 7880:7880 -p 7881:7881 -p 7882:7882/udp \
  livekit/livekit-server --dev
```

### Step 5: Configure Functions (2 minutes)
```bash
cd /repos/tres3/3v-repo/functions

# Create .env from template
cp .env.example .env

# Edit .env and add:
# - Firebase service account (from Firebase Console > Settings > Service Accounts)
# - LiveKit credentials (from step 4)
nano .env

# Install dependencies and deploy
npm install
firebase deploy --only functions
```

### Step 6: Test the App! 🎉
```bash
cd /repos/tres3/3v-repo/tres_flutter
flutter run
```

---

## 📝 What You Need

### Firebase Credentials
```
Location: Firebase Console > Project Settings > Service Accounts
What: Download JSON service account key
Used for: Backend functions authentication
```

### LiveKit Credentials
```
Location: https://cloud.livekit.io/ dashboard
What: API Key, API Secret, WebSocket URL
Used for: Video call infrastructure
```

---

## ✅ Verification Checklist

After running the setup script, verify these files exist:

```bash
# Flutter configuration
✅ lib/firebase_options.dart
✅ lib/config/environment.dart
✅ android/app/google-services.json
✅ ios/Runner/GoogleService-Info.plist

# Functions configuration
✅ functions/.env
✅ functions/node_modules/
```

---

## 🔧 Manual Setup (If Script Fails)

### 1. Install Tools
```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
```

### 2. Configure FlutterFire
```bash
cd /repos/tres3/3v-repo/tres_flutter
firebase login
flutterfire configure \
  --project=YOUR_PROJECT_ID \
  --platforms=android,ios,web \
  --out=lib/firebase_options.dart \
  --android-package-name=com.threeveesocial.tresvideo \
  --ios-bundle-id=com.threeveesocial.tresvideo
```

### 3. Update Environment
Edit `lib/config/environment.dart`:
```dart
static const String liveKitUrl = 'wss://YOUR-SERVER.livekit.cloud';
static const String functionsBaseUrl = 
    'https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net';
```

### 4. Deploy Rules
```bash
cd /repos/tres3/3v-repo
firebase deploy --only firestore:rules
```

---

## 🐛 Troubleshooting

### "Firebase not configured"
```bash
# Re-run flutterfire configure
cd /repos/tres3/3v-repo/tres_flutter
flutterfire configure
```

### "LiveKit connection failed"
```
Check:
1. WebSocket URL format: wss:// not https://
2. API Key/Secret are correct
3. Firewall allows WebSocket connections
```

### "Functions not working"
```bash
# Check function logs
firebase functions:log

# Verify deployment
firebase functions:list

# Test locally
firebase emulators:start --only functions
```

### "ML Kit not working"
```
Note: ML features require REAL DEVICE with camera
Emulators have limited ML Kit support
```

---

## 📊 Cost Breakdown (Free Tier)

**Firebase Spark Plan (FREE):**
- ✅ 10K Firestore writes/day
- ✅ 50K Firestore reads/day
- ✅ 1GB Storage
- ✅ 10GB/month transfer
- ✅ 125K function invocations/month

**LiveKit Cloud (FREE):**
- ✅ 10,000 participant minutes/month
- ✅ Unlimited rooms

**Upgrade needed when:**
- More than ~100 users/day
- Recording storage > 1GB
- Heavy function usage

---

## 🎯 Success Indicators

You'll know setup worked when:
- ✅ App builds without errors
- ✅ You can sign up with email/password
- ✅ You can create a video call room
- ✅ You can see yourself in video preview
- ✅ ML filters work (blur, beauty)
- ✅ Chat messages appear in Firestore

---

## 📚 Additional Resources

- **Full Guide**: See `FIREBASE_SETUP_GUIDE.md`
- **Firebase Docs**: https://firebase.google.com/docs/flutter
- **LiveKit Docs**: https://docs.livekit.io/
- **FlutterFire**: https://firebase.flutter.dev/

---

## 🆘 Need Help?

1. Check `FIREBASE_SETUP_GUIDE.md` for detailed instructions
2. Check Firebase Console logs
3. Check function logs: `firebase functions:log`
4. Test with Flutter DevTools: `flutter run --verbose`

---

**Estimated Total Time: 15-30 minutes**
**Difficulty: Easy (automated script) to Medium (manual)**
