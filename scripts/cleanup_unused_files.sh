#!/bin/bash
# ✅ OPTIMIZATION: Automated cleanup script for unused files
# Generated as part of optimization audit implementation

set -e

echo "🧹 Cleaning up unused files..."
echo "=================================="

cd tres_flutter

# ✅ Remove backup files (already done but script for future)
echo "🗑️  Removing backup files..."
find lib/screens -name "*_old*.dart" -type f -delete 2>/dev/null || true
find lib/screens -name "*_backup*.dart" -type f -delete 2>/dev/null || true
find lib/screens -name "*.bak" -type f -delete 2>/dev/null || true

# ✅ Remove unused imports (requires manual review)
echo "📋 Checking for unused imports..."
flutter analyze --no-pub

# ✅ Update dependencies
echo "📦 Updating dependencies..."
flutter pub upgrade --major-versions

# ✅ Clean build cache
echo "🧹 Cleaning build cache..."
flutter clean
rm -rf .dart_tool/build/
rm -rf build/

echo "✅ Cleanup completed!"
echo "📊 Files cleaned:"
echo "   - Backup files removed"
echo "   - Build cache cleared"
echo "   - Dependencies updated"
echo ""
echo "⚠️  Manual review required:"
echo "   - Check flutter analyze results for unused imports"
echo "   - Test the application after cleanup"

cd ..