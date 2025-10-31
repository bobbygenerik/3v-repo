# What I Need From You for Firebase Setup

## 🎯 Quick Overview
I need 5 things to complete the setup. Let's go through them one by one.

---

## ✅ 1. Firebase Project ID

**Where to find it:**
1. Go to: https://console.firebase.google.com/
2. Click on your project
3. Click the ⚙️ gear icon → "Project settings"
4. Look for **"Project ID"** (not project name)

**Example:** `my-video-app-12345`

```
👉 Your Project ID: ___________________________
```

---

## ✅ 2. Enable Firebase Services

**You need to enable these in Firebase Console:**

### Authentication (Build → Authentication)
1. Click "Get started"
2. Enable **Email/Password**
3. Enable **Google** (optional but recommended)
4. Enable **Anonymous** (for guest access)

### Firestore Database (Build → Firestore Database)
1. Click "Create database"
2. Select **"Production mode"**
3. Choose **location** (e.g., us-central, europe-west)

### Storage (Build → Storage)
1. Click "Get started"
2. Select **"Production mode"**
3. Use **same location** as Firestore

### Cloud Messaging
✅ Automatically enabled (nothing to do)

```
☐ Authentication enabled
☐ Firestore Database created
☐ Storage enabled
☐ Location chosen: _______________
```

---

## ✅ 3. Firebase Service Account (for Backend Functions)

**Where to get it:**
1. Firebase Console → ⚙️ → "Project settings"
2. Click **"Service accounts"** tab
3. Click **"Generate new private key"**
4. Download the JSON file

**What I need from that JSON file:**
```json
{
  "project_id": "your-project-id",           ← Copy this
  "client_email": "firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com",  ← Copy this
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"    ← Copy this (entire thing)
}
```

---

## ✅ 4. LiveKit Credentials

**Option A: LiveKit Cloud (Recommended)**

1. Go to: https://cloud.livekit.io/
2. Sign up (free account)
3. Create a project
4. Copy these 3 values:
   - **API Key** (starts with `API`)
   - **API Secret** (long random string)
   - **WebSocket URL** (format: `wss://your-project.livekit.cloud`)

**Free tier includes:** 10,000 participant minutes/month

```
👉 LIVEKIT_API_KEY: ___________________________
👉 LIVEKIT_API_SECRET: ________________________
👉 LIVEKIT_URL: wss://_______________________
```

**Option B: Self-Hosted (Advanced)**
```bash
docker run -d -p 7880:7880 livekit/livekit-server --dev
# Then use: ws://localhost:7880
```

---

## ✅ 5. Confirmation Checklist

Before running the setup script, confirm:

```
☐ I have my Firebase Project ID
☐ I've enabled Authentication (Email, Google, Anonymous)
☐ I've created Firestore Database
☐ I've enabled Storage
☐ I've downloaded the service account JSON file
☐ I have LiveKit credentials (or will set up later)
```

---

## 🚀 Ready to Run Setup?

Once you have items 1-4 above, we can run:

```bash
cd /repos/tres3/3v-repo/tres_flutter
./setup_interactive.sh
```

**The script will:**
- ✅ Login to Firebase
- ✅ Configure FlutterFire (creates all config files)
- ✅ Update environment.dart with your project ID
- ✅ Deploy Firestore security rules
- ✅ Set up functions/.env
- ✅ Deploy backend functions

**Time required:** 10-15 minutes

---

## 📝 Quick Command Version (Manual)

If you prefer to do it manually:

```bash
# 1. Login to Firebase
export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
export PATH="$PATH":"$HOME/.pub-cache/bin"
firebase login --no-localhost

# 2. Configure FlutterFire (replace YOUR_PROJECT_ID)
flutterfire configure \
  --project=YOUR_PROJECT_ID \
  --platforms=android,ios,web \
  --out=lib/firebase_options.dart \
  --android-package-name=com.threeveesocial.tresvideo \
  --ios-bundle-id=com.threeveesocial.tresvideo

# 3. Deploy Firestore rules
cd /repos/tres3/3v-repo
firebase use YOUR_PROJECT_ID
firebase deploy --only firestore:rules

# 4. Set up functions
cd functions
cp .env.example .env
# Edit .env with your credentials
npm install
firebase deploy --only functions

# 5. Test
cd ../tres_flutter
flutter pub get
flutter run
```

---

## 🆘 Troubleshooting

**"Firebase login fails"**
- Use `firebase login --no-localhost` if on server

**"FlutterFire configure fails"**
- Make sure project exists in Firebase Console
- Check project ID is correct (not display name)

**"Can't find flutterfire command"**
- Run: `export PATH="$PATH":"$HOME/.pub-cache/bin"`

**"Functions deploy fails"**
- Check functions/.env has all required values
- Verify service account JSON is valid

---

## 📞 Current Status

What do you have ready?
- [ ] Firebase Project ID
- [ ] Services enabled (Auth, Firestore, Storage)
- [ ] Service account JSON file
- [ ] LiveKit credentials

**Let me know what you have and I'll guide you through the rest!**
