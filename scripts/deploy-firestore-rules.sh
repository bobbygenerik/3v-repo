#!/bin/bash
# Deploy Firestore security rules to Firebase

echo "🔒 Deploying Firestore Security Rules..."
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found. Installing..."
    npm install -g firebase-tools
fi

# Deploy rules
echo "📤 Deploying rules to Firebase..."
firebase deploy --only firestore:rules

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Firestore rules deployed successfully!"
    echo ""
    echo "The following permissions are now active:"
    echo "  • Users can read all user profiles (authenticated)"
    echo "  • Users can write to their own profile"
    echo "  • Users can send call invites to others (write to callSignals)"
    echo "  • Users can read their own call signals"
    echo ""
else
    echo ""
    echo "❌ Deployment failed. Please check your Firebase login:"
    echo "   Run: firebase login"
    echo ""
fi
