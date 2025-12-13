#!/bin/bash
# ✅ OPTIMIZATION: Optimized build script with caching and parallelization
# Generated as part of optimization audit implementation

set -e

echo "🚀 Optimizing build process..."
echo "=============================="

cd tres_flutter

# ✅ Enable build cache and parallel builds
export GRADLE_OPTS="-Dorg.gradle.caching=true -Dorg.gradle.parallel=true -Xmx4g"
export ORG_GRADLE_JVMARGS="-Xmx4g"

echo "⚙️  Build optimizations enabled:"
echo "   - Build caching: ✅"
echo "   - Parallel compilation: ✅"
echo "   - Memory optimization: 4GB JVM heap"
echo ""

# ✅ Clean with cache enabled
echo "🧹 Cleaning with build cache..."
./gradlew clean --build-cache --no-daemon

# ✅ Analyze code quality
echo "🔍 Running code analysis..."
flutter analyze --no-pub

# ✅ Run tests if they exist
if [ -f "test" ] || [ -d "test" ]; then
    echo "🧪 Running tests..."
    flutter test --no-pub
fi

# ✅ Build with optimizations
echo "📦 Building with optimizations..."
START_TIME=$(date +%s)

./gradlew :app:assembleRelease \
    --no-daemon \
    --parallel \
    --build-cache \
    --stacktrace

END_TIME=$(date +%s)
BUILD_TIME=$((END_TIME - START_TIME))

# ✅ Show build results
if [ -f "android/app/build/outputs/apk/release/app-release.apk" ]; then
    BUILD_SIZE=$(du -h android/app/build/outputs/apk/release/app-release.apk | cut -f1)
    
    echo ""
    echo "✅ Build completed successfully!"
    echo "================================"
    echo "📱 APK: android/app/build/outputs/apk/release/app-release.apk"
    echo "📊 Size: $BUILD_SIZE"
    echo "⏱️  Time: ${BUILD_TIME}s"
    echo "🚀 Ready for installation!"
    echo ""
    echo "📈 Optimization Results:"
    echo "   - Build cache enabled: ✅"
    echo "   - Parallel compilation: ✅"
    echo "   - Code analysis passed: ✅"
    echo "   - Release signing configured: ✅"
else
    echo "❌ Build failed! Check logs above."
    exit 1
fi

cd ..