#!/bin/bash

# Simple Firebase Setup Guide
# This will walk you through the process step by step

set -e

echo "════════════════════════════════════════════════════"
echo "   🔥 Firebase Setup for 3V Video Calls"
echo "════════════════════════════════════════════════════"
echo ""

# Set up environment
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
export PATH="$PATH":"$HOME/.pub-cache/bin"

echo "✅ Tools installed:"
echo "   - Firebase CLI: $(firebase --version 2>/dev/null || echo 'installing...')"
echo "   - FlutterFire CLI: $(flutterfire --version 2>/dev/null || echo 'ready')"
echo ""

echo "════════════════════════════════════════════════════"
echo "📋 Step 1: Firebase Console Setup"
echo "════════════════════════════════════════════════════"
echo ""
echo "Please complete these in Firebase Console (https://console.firebase.google.com):"
echo ""
echo "1. ☐ Go to your project"
echo "2. ☐ Click 'Build' → 'Authentication'"
echo "3. ☐ Click 'Get started'"
echo "4. ☐ Enable these sign-in methods:"
echo "      - Email/Password"
echo "      - Google (optional but recommended)"
echo "      - Anonymous (for guest access)"
echo ""
echo "5. ☐ Click 'Build' → 'Firestore Database'"
echo "6. ☐ Click 'Create database'"
echo "7. ☐ Select 'Production mode'"
echo "8. ☐ Choose location (closest to your users)"
echo ""
echo "9. ☐ Click 'Build' → 'Storage'"
echo "10. ☐ Click 'Get started'"
echo "11. ☐ Select 'Production mode'"
echo "12. ☐ Use same location as Firestore"
echo ""
echo "13. ☐ Cloud Messaging is automatically enabled"
echo ""

read -p "Press ENTER when you've completed the above steps..."

echo ""
echo "════════════════════════════════════════════════════"
echo "📋 Step 2: Get Your Project ID"
echo "════════════════════════════════════════════════════"
echo ""
echo "In Firebase Console:"
echo "  → Click the gear icon (Settings)"
echo "  → Project settings"
echo "  → Look for 'Project ID'"
echo ""

read -p "Enter your Firebase Project ID: " PROJECT_ID

if [ -z "$PROJECT_ID" ]; then
    echo "❌ Error: Project ID cannot be empty"
    exit 1
fi

echo ""
echo "Using project: $PROJECT_ID"
echo ""

echo "════════════════════════════════════════════════════"
echo "📋 Step 3: Firebase Login"
echo "════════════════════════════════════════════════════"
echo ""
echo "This will open your browser to login to Firebase..."
read -p "Press ENTER to continue..."

firebase login --no-localhost

echo ""
echo "════════════════════════════════════════════════════"
echo "📋 Step 4: Configure FlutterFire"
echo "════════════════════════════════════════════════════"
echo ""
echo "This will:"
echo "  ✓ Create lib/firebase_options.dart"
echo "  ✓ Download android/app/google-services.json"
echo "  ✓ Download ios/Runner/GoogleService-Info.plist"
echo ""

flutterfire configure \
  --project="$PROJECT_ID" \
  --platforms=android,ios,web \
  --out=lib/firebase_options.dart \
  --android-package-name=com.threeveesocial.tresvideo \
  --ios-bundle-id=com.threeveesocial.tresvideo \
  --yes

echo ""
echo "════════════════════════════════════════════════════"
echo "📋 Step 5: Update Environment Config"
echo "════════════════════════════════════════════════════"
echo ""

# Update environment.dart with project ID
FUNCTIONS_URL="https://us-central1-$PROJECT_ID.cloudfunctions.net"
sed -i "s|https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net|$FUNCTIONS_URL|g" lib/config/environment.dart

echo "✅ Updated lib/config/environment.dart"
echo "   Functions URL: $FUNCTIONS_URL"
echo ""

echo "════════════════════════════════════════════════════"
echo "📋 Step 6: Deploy Firestore Security Rules"
echo "════════════════════════════════════════════════════"
echo ""

cd ..
firebase use "$PROJECT_ID"

echo "Deploying Firestore security rules..."
firebase deploy --only firestore:rules

cd tres_flutter

echo ""
echo "════════════════════════════════════════════════════"
echo "📋 Step 7: LiveKit Setup"
echo "════════════════════════════════════════════════════"
echo ""
echo "You need LiveKit for video calling. Choose an option:"
echo ""
echo "Option A: LiveKit Cloud (Recommended - Easy)"
echo "  1. Go to: https://cloud.livekit.io/"
echo "  2. Sign up (free tier: 10K minutes/month)"
echo "  3. Create a project"
echo "  4. Copy API Key, API Secret, WebSocket URL"
echo ""
echo "Option B: Self-Hosted (Advanced)"
echo "  Run: docker run -d -p 7880:7880 livekit/livekit-server --dev"
echo ""

read -p "Do you have LiveKit credentials? (y/n): " HAS_LIVEKIT

if [ "$HAS_LIVEKIT" = "y" ] || [ "$HAS_LIVEKIT" = "Y" ]; then
    read -p "LiveKit WebSocket URL (e.g., wss://your-project.livekit.cloud): " LIVEKIT_URL
    
    if [ ! -z "$LIVEKIT_URL" ]; then
        sed -i "s|wss://your-livekit-server.com|$LIVEKIT_URL|g" lib/config/environment.dart
        echo "✅ Updated LiveKit URL in environment.dart"
    fi
else
    echo ""
    echo "⚠️  You'll need to set up LiveKit before the app will work."
    echo "   Edit lib/config/environment.dart later with your LiveKit URL"
fi

echo ""
echo "════════════════════════════════════════════════════"
echo "📋 Step 8: Backend Functions Setup"
echo "════════════════════════════════════════════════════"
echo ""

cd ../functions

if [ ! -f ".env" ]; then
    echo "Creating functions/.env file..."
    cp .env.example .env
    echo "✅ Created functions/.env"
fi

echo ""
echo "You need to edit functions/.env with:"
echo ""
echo "1. Firebase Service Account:"
echo "   → Firebase Console → Project Settings → Service Accounts"
echo "   → Click 'Generate new private key'"
echo "   → Download JSON file"
echo "   → Copy these values to .env:"
echo "     - project_id → FIREBASE_PROJECT_ID"
echo "     - client_email → FIREBASE_CLIENT_EMAIL"
echo "     - private_key → FIREBASE_PRIVATE_KEY"
echo ""
echo "2. LiveKit Credentials:"
echo "   → Copy from LiveKit dashboard"
echo "     - LIVEKIT_API_KEY"
echo "     - LIVEKIT_API_SECRET"
echo "     - LIVEKIT_URL"
echo ""

read -p "Press ENTER when you've edited functions/.env..."

echo ""
echo "Installing function dependencies..."
npm install

echo ""
read -p "Deploy functions now? (y/n): " DEPLOY_FUNCTIONS

if [ "$DEPLOY_FUNCTIONS" = "y" ] || [ "$DEPLOY_FUNCTIONS" = "Y" ]; then
    firebase deploy --only functions
fi

cd ../tres_flutter

echo ""
echo "════════════════════════════════════════════════════"
echo "✅ Setup Complete!"
echo "════════════════════════════════════════════════════"
echo ""
echo "Files created:"
echo "  ✅ lib/firebase_options.dart"
echo "  ✅ lib/config/environment.dart (updated)"
echo "  ✅ android/app/google-services.json"
echo "  ✅ ios/Runner/GoogleService-Info.plist"
echo "  ✅ functions/.env"
echo ""
echo "Next steps:"
echo "  1. Run: flutter pub get"
echo "  2. Run: flutter run"
echo "  3. Test on a REAL DEVICE (ML features need real camera)"
echo ""
echo "See INTEGRATION_CHECKLIST.md for testing guide"
echo ""
