#!/usr/bin/env bash
set -euo pipefail

# Simple crash log capture utility for Android apps.
#
# Usage:
#   bash scripts/capture-crash-log.sh [packageName]
#
# Env vars:
#   OUT_DIR      Directory to write logs (default: logs)
#   SKIP_LAUNCH  If set to 1, skip auto-launching the app (default: 0)
#
# Behavior:
# - Waits for a connected device
# - Clears logcat
# - Force-stops and launches the app (unless SKIP_LAUNCH=1)
# - Resolves the app PID and runs `adb logcat --pid` to avoid noise
# - Falls back to package/crash-pattern filtering if PID isn't found
# - Writes full capture and a crash-only extract under OUT_DIR

PACKAGE="${1:-com.example.threevchat}"
OUT_DIR="${OUT_DIR:-logs}"
TS="$(date +%Y%m%d-%H%M%S)"
OUT_RAW="$OUT_DIR/${TS}-${PACKAGE}-raw.log"
OUT_FOCUSED="$OUT_DIR/${TS}-${PACKAGE}-crash.log"

need_cmd() { command -v "$1" >/dev/null 2>&1; }

if ! need_cmd adb; then
  echo "Error: adb not found in PATH. Install platform-tools or run 'make sdk' first." >&2
  exit 127
fi

mkdir -p "$OUT_DIR"

echo "Checking for connected devices..."
CONNECTED_DEVICES=$(adb devices | awk 'NR>1 && $2=="device" {print $1}')
if [[ -z "$CONNECTED_DEVICES" ]]; then
  cat >&2 <<EOF
No device detected by adb.

If you're in a remote dev container (Codespaces/CI), it cannot access your local USB device.
Please run this script on your local machine where the phone is connected, or use Android Studio Logcat.

Local quick check:
  1) Enable Developer options and USB debugging on the phone.
  2) Connect via USB and accept the RSA prompt.
  3) Run: adb devices
  4) Re-run this script.

EOF
  exit 1
fi

echo "Clearing existing logcat buffer..."
adb logcat -c || true

if [[ "${SKIP_LAUNCH:-0}" != "1" ]]; then
  echo "Force-stopping and launching $PACKAGE..."
  adb shell am force-stop "$PACKAGE" || true
  # Try to launch the default launcher activity
  adb shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
fi

echo "Resolving PID for $PACKAGE..."
PID=""
for _ in {1..20}; do
  PID=$(adb shell pidof -s "$PACKAGE" | tr -d '\r')
  [[ -n "$PID" ]] && break
  sleep 0.25
done

echo "Capturing logs to $OUT_RAW"
echo "Reproduce the issue now; press Ctrl-C here after the crash occurs."

# Disable immediate exit during capture so Ctrl-C doesn't abort post-processing
set +e
if [[ -n "$PID" ]]; then
  echo "Using PID filter: $PID"
  adb logcat --pid="$PID" -v time | tee "$OUT_RAW"
else
  echo "PID not found; falling back to package/crash filter."
  # Note: fallback will still include some noise but keeps common crash lines
  adb logcat -v time | grep -E --line-buffered "(FATAL EXCEPTION|Fatal signal|ANR in|am_crash|\b$PACKAGE\b)" | tee "$OUT_RAW"
fi
CAPTURE_CODE=$?
set -e

echo "Extracting crash blocks to $OUT_FOCUSED..."
awk '
  /FATAL EXCEPTION|Fatal signal|ANR in/ { printing=1 }
  printing { print }
  /Backtrace:|backtrace:|--------- beginning of crash|\(SIG/ { if (printing) { printing=0; print "" } }
' "$OUT_RAW" > "$OUT_FOCUSED" || true

echo "Done."
echo "Raw log: $OUT_RAW"
echo "Crash extract: $OUT_FOCUSED"
if [[ -s "$OUT_FOCUSED" ]]; then
  echo "Potential crash details captured. Please share the crash extract file."
else
  echo "No obvious crash block detected. Please share the last ~200 lines of the raw log file."
fi

exit "$CAPTURE_CODE"
