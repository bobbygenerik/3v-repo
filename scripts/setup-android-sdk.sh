#!/usr/bin/env bash
set -euo pipefail

# Simple Android SDK installation script for Codespaces
# - Installs JDK 17 if missing
# - Installs commandline-tools, platform-tools, platform 35, build-tools 35.0.0
# - Configures ANDROID_SDK_ROOT and PATH in ~/.bashrc
# - Writes/updates local.properties with correct sdk.dir (without nuking existing keys)

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

ensure_pkg() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    echo "Installing package: $pkg"
    sudo apt-get update -y
    sudo apt-get install -y "$pkg"
  fi
}

# Ensure curl and unzip exist
if ! need_cmd curl; then ensure_pkg curl; fi
if ! need_cmd unzip; then ensure_pkg unzip; fi

# Ensure JDK 17
JAVA_OK=false
if need_cmd java; then
  if java -version 2>&1 | grep -q '"17\.'; then JAVA_OK=true; fi
fi
if [ "$JAVA_OK" = false ]; then
  echo "JDK 17 not found; installing OpenJDK 17..."
  ensure_pkg openjdk-17-jdk
fi

# Ensure JAVA_HOME and PATH point to JDK 17 to avoid class version mismatches
if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
  export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
elif [ -d "/usr/lib/jvm/java-17-openjdk" ]; then
  export JAVA_HOME="/usr/lib/jvm/java-17-openjdk"
else
  # Best-effort: derive from java binary
  JAVA_BIN_PATH="$(command -v java || true)"
  if [[ -n "$JAVA_BIN_PATH" ]]; then
    export JAVA_HOME="$(readlink -f "$JAVA_BIN_PATH" | sed -E 's#/bin/java$##')"
  fi
fi
export PATH="$JAVA_HOME/bin:$PATH"

SDK_ROOT="$HOME/android-sdk"
CMDLINE_TOOLS_VERSION="11076708_latest" # as of 2025-10
CMDLINE_ZIP="commandlinetools-linux-${CMDLINE_TOOLS_VERSION}.zip"
CMDLINE_URL="https://dl.google.com/android/repository/${CMDLINE_ZIP}"

mkdir -p "$SDK_ROOT"
cd "$SDK_ROOT"

if [ ! -d "$SDK_ROOT/cmdline-tools/latest" ]; then
  echo "Downloading Android command-line tools..."
  curl -fsSL -o "$CMDLINE_ZIP" "$CMDLINE_URL"
  rm -rf "$SDK_ROOT/cmdline-tools"
  mkdir -p "$SDK_ROOT/cmdline-tools"
  unzip -q "$CMDLINE_ZIP" -d "$SDK_ROOT/cmdline-tools"
  # The zip extracts to cmdline-tools; we want it under cmdline-tools/latest
  if [ -d "$SDK_ROOT/cmdline-tools/cmdline-tools" ]; then
    mv "$SDK_ROOT/cmdline-tools/cmdline-tools" "$SDK_ROOT/cmdline-tools/latest"
  fi
  rm -f "$CMDLINE_ZIP"
fi

export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

yes | sdkmanager --licenses > /dev/null || true

# Install required packages
PACKAGES=(
  "platform-tools"
  "platforms;android-35"
  "build-tools;35.0.0"
)

echo "Installing Android SDK packages: ${PACKAGES[*]}"
for pkg in "${PACKAGES[@]}"; do
  sdkmanager "$pkg"
done

# Persist environment variables to .bashrc (idempotent)
PROFILE="$HOME/.bashrc"
if ! grep -q "ANDROID_SDK_ROOT" "$PROFILE"; then
  {
    echo ''
    echo '# Android SDK (added by setup-android-sdk.sh)'
    echo "export ANDROID_SDK_ROOT=\"$SDK_ROOT\""
    echo 'export ANDROID_HOME="$ANDROID_SDK_ROOT"'
    echo 'export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"'
  } >> "$PROFILE"
fi

## Write/update local.properties with the correct sdk.dir without overwriting other keys
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LP="$REPO_ROOT/local.properties"
touch "$LP"
if grep -q '^sdk.dir=' "$LP"; then
  sed -i "s#^sdk.dir=.*#sdk.dir=$ANDROID_SDK_ROOT#" "$LP"
else
  echo "sdk.dir=$ANDROID_SDK_ROOT" >> "$LP"
fi

printf "\nAndroid SDK installed at: %s\n" "$ANDROID_SDK_ROOT"
sdkmanager --list | head -n 30 || true

echo "\nDone. Open a new shell or 'source ~/.bashrc' before building. local.properties updated."
