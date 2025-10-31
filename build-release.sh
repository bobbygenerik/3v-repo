#!/bin/bash
# Build script for Tres3 Video Calling App

set -e

echo "🔨 Building Tres3 App..."
echo "================================"

# Check for local.properties
if [ ! -f "local.properties" ]; then
    echo "❌ Error: local.properties not found!"
    echo "📝 Copy local.properties.example and add your credentials"
    exit 1
fi

# Check for google-services.json
if [ ! -f "app/google-services.json" ]; then
    echo "⚠️  Warning: app/google-services.json not found!"
    echo "   App may not connect to Firebase"
fi

# Clean previous build
echo "🧹 Cleaning previous build..."
./gradlew clean --no-daemon

# Build debug APK
echo "📦 Building debug APK..."
./gradlew :app:assembleDebug --no-daemon --stacktrace

# Check if build succeeded
if [ -f "app/build/outputs/apk/debug/app-debug.apk" ]; then
    echo ""
    echo "✅ Build successful!"
    echo "================================"
    echo "📱 APK Location:"
    echo "   app/build/outputs/apk/debug/app-debug.apk"
    echo ""
    echo "📊 APK Size:"
    ls -lh app/build/outputs/apk/debug/app-debug.apk | awk '{print "   " $5}'
    echo ""
    echo "🚀 To install on device:"
    echo "   adb install app/build/outputs/apk/debug/app-debug.apk"
    echo ""
else
    echo "❌ Build failed! Check logs above."
    exit 1
fi
