#!/bin/bash

# Firebase Setup Script for Flutter
# This script automates the initial Firebase setup process

set -e

echo "🔥 Firebase Setup Script for 3V Video Calls"
echo "============================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo "📋 Checking prerequisites..."

# Check Flutter
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Flutter found${NC}"

# Check Firebase CLI
if ! command -v firebase &> /dev/null; then
    echo -e "${YELLOW}⚠️  Firebase CLI not found. Installing...${NC}"
    npm install -g firebase-tools
fi
echo -e "${GREEN}✅ Firebase CLI found${NC}"

# Check FlutterFire CLI
if ! command -v flutterfire &> /dev/null; then
    echo -e "${YELLOW}⚠️  FlutterFire CLI not found. Installing...${NC}"
    dart pub global activate flutterfire_cli
fi
echo -e "${GREEN}✅ FlutterFire CLI found${NC}"

echo ""
echo "============================================"
echo ""

# Get project directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FLUTTER_DIR="$SCRIPT_DIR"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$FLUTTER_DIR"

# Login to Firebase
echo "🔐 Logging into Firebase..."
echo "   (This will open your browser)"
firebase login

echo ""
echo "============================================"
echo ""

# Get Firebase project ID
echo "📝 Enter your Firebase project ID:"
echo "   (You can find this in Firebase Console > Project Settings)"
read -p "Project ID: " PROJECT_ID

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}❌ Project ID cannot be empty${NC}"
    exit 1
fi

echo ""
echo "============================================"
echo ""

# Configure FlutterFire
echo "🔧 Configuring FlutterFire..."
echo "   This will create firebase_options.dart and download config files"

flutterfire configure \
  --project="$PROJECT_ID" \
  --platforms=android,ios,web \
  --out=lib/firebase_options.dart \
  --android-package-name=com.threeveesocial.tresvideo \
  --ios-bundle-id=com.threeveesocial.tresvideo \
  --yes

echo ""
echo "============================================"
echo ""

# Verify files were created
echo "✅ Verifying configuration files..."

if [ -f "lib/firebase_options.dart" ]; then
    echo -e "${GREEN}✅ lib/firebase_options.dart created${NC}"
else
    echo -e "${RED}❌ lib/firebase_options.dart not found${NC}"
    exit 1
fi

if [ -f "android/app/google-services.json" ]; then
    echo -e "${GREEN}✅ android/app/google-services.json created${NC}"
else
    echo -e "${RED}❌ android/app/google-services.json not found${NC}"
    exit 1
fi

if [ -f "ios/Runner/GoogleService-Info.plist" ]; then
    echo -e "${GREEN}✅ ios/Runner/GoogleService-Info.plist created${NC}"
else
    echo -e "${YELLOW}⚠️  ios/Runner/GoogleService-Info.plist not found (iOS config may need manual setup)${NC}"
fi

echo ""
echo "============================================"
echo ""

# Get LiveKit configuration
echo "🎥 LiveKit Configuration"
echo ""
echo "Do you have LiveKit credentials? (y/n)"
read -p "> " HAS_LIVEKIT

if [ "$HAS_LIVEKIT" = "y" ] || [ "$HAS_LIVEKIT" = "Y" ]; then
    echo ""
    read -p "LiveKit WebSocket URL (e.g., wss://your-server.com): " LIVEKIT_URL
    
    # Update environment.dart
    if [ ! -z "$LIVEKIT_URL" ]; then
        sed -i.bak "s|wss://your-livekit-server.com|$LIVEKIT_URL|g" lib/config/environment.dart
        echo -e "${GREEN}✅ Updated LiveKit URL in environment.dart${NC}"
    fi
fi

# Update Functions URL
FUNCTIONS_URL="https://us-central1-$PROJECT_ID.cloudfunctions.net"
sed -i.bak "s|https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net|$FUNCTIONS_URL|g" lib/config/environment.dart
echo -e "${GREEN}✅ Updated Functions URL in environment.dart${NC}"

# Clean up backup files
rm -f lib/config/environment.dart.bak

echo ""
echo "============================================"
echo ""

# Deploy Firestore rules
echo "📝 Do you want to deploy Firestore security rules? (y/n)"
read -p "> " DEPLOY_RULES

if [ "$DEPLOY_RULES" = "y" ] || [ "$DEPLOY_RULES" = "Y" ]; then
    cd "$REPO_ROOT"
    firebase use "$PROJECT_ID"
    firebase deploy --only firestore:rules
    cd "$FLUTTER_DIR"
fi

echo ""
echo "============================================"
echo ""

# Set up Firebase Functions
echo "⚡ Do you want to set up Firebase Functions? (y/n)"
read -p "> " SETUP_FUNCTIONS

if [ "$SETUP_FUNCTIONS" = "y" ] || [ "$SETUP_FUNCTIONS" = "Y" ]; then
    cd "$REPO_ROOT/functions"
    
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example .env
            echo -e "${GREEN}✅ Created .env file from .env.example${NC}"
            echo -e "${YELLOW}⚠️  Please edit functions/.env with your credentials${NC}"
        else
            echo -e "${YELLOW}⚠️  .env.example not found. Please create .env manually${NC}"
        fi
    fi
    
    echo "📦 Installing function dependencies..."
    npm install
    
    echo ""
    echo "Do you want to deploy functions now? (y/n)"
    read -p "> " DEPLOY_FUNCTIONS
    
    if [ "$DEPLOY_FUNCTIONS" = "y" ] || [ "$DEPLOY_FUNCTIONS" = "Y" ]; then
        firebase use "$PROJECT_ID"
        firebase deploy --only functions
    fi
    
    cd "$FLUTTER_DIR"
fi

echo ""
echo "============================================"
echo ""

# Install Flutter dependencies
echo "📦 Installing Flutter dependencies..."
flutter pub get

echo ""
echo "============================================"
echo ""

# iOS setup reminder
echo "📱 iOS Setup Reminder:"
echo "   1. Open ios/Runner.xcworkspace in Xcode"
echo "   2. Set your development team"
echo "   3. Update bundle identifier if needed"
echo "   4. Verify GoogleService-Info.plist is in Runner folder"
echo ""

# Final instructions
echo "============================================"
echo "✅ Firebase setup complete!"
echo "============================================"
echo ""
echo "📝 Next steps:"
echo ""
echo "1. Enable Firebase services in console:"
echo "   • Authentication (Email/Password, Google, Anonymous)"
echo "   • Firestore Database"
echo "   • Storage"
echo "   • Cloud Messaging"
echo ""
echo "2. Set up LiveKit (if not done):"
echo "   • Sign up at https://cloud.livekit.io/"
echo "   • Get API Key, Secret, and URL"
echo "   • Update functions/.env"
echo ""
echo "3. Update functions/.env with:"
echo "   • Firebase service account credentials"
echo "   • LiveKit credentials"
echo ""
echo "4. Test the app:"
echo "   flutter run"
echo ""
echo "📚 See FIREBASE_SETUP_GUIDE.md for detailed instructions"
echo ""
