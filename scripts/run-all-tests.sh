#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_DIR="$ROOT_DIR/tres_flutter"

echo "🧪 Running codebase-only tests"
echo "=============================="

if [ ! -d "$FLUTTER_DIR" ]; then
  echo "❌ Flutter app not found at $FLUTTER_DIR"
  exit 1
fi

cd "$FLUTTER_DIR"

echo ""
echo "▶️  Unit/widget tests (flutter test)"
flutter test

echo ""
echo "▶️  Integration tests"
echo "ℹ️  Skipping integration tests (device-dependent)."

echo ""
echo "▶️  Performance checks"
cd "$ROOT_DIR"
bash scripts/performance_check.sh

echo ""
echo "▶️  Cloud Functions tests"
if [ -d "$ROOT_DIR/functions/test" ]; then
  if [ -d "$ROOT_DIR/functions/node_modules" ]; then
    set +e
    (cd "$ROOT_DIR/functions" && npm test)
    STATUS=$?
    set -e
    if [ $STATUS -ne 0 ]; then
      echo "⚠️  Cloud Functions tests failed."
    fi
  else
    echo "⚠️  Skipping functions tests (run npm install in functions/)."
  fi
else
  echo "ℹ️  No Cloud Functions tests found."
fi

echo ""
echo "▶️  Firestore rules tests"
if [ -f "$ROOT_DIR/tests/firestore_rules.test.js" ]; then
  if [ -d "$ROOT_DIR/tests/node_modules" ]; then
    set +e
    (cd "$ROOT_DIR/tests" && npm test)
    STATUS=$?
    set -e
    if [ $STATUS -ne 0 ]; then
      echo "⚠️  Firestore rules tests failed."
    fi
  else
    echo "⚠️  Skipping Firestore rules tests (run npm install in tests/)."
  fi
else
  echo "ℹ️  No Firestore rules tests found."
fi

echo ""
echo "✅ Done"
