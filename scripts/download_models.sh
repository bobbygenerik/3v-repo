#!/usr/bin/env bash
# download_models.sh — Download LiteRT model files for on-device ML features.
# Run from the repo root:  bash scripts/download_models.sh
set -euo pipefail

MODELS_DIR="tres_flutter/android/app/src/main/assets/models"

echo "📦 Downloading LiteRT models to $MODELS_DIR ..."
mkdir -p "$MODELS_DIR"
cd "$MODELS_DIR"

# ── Selfie segmentation (background blur) ─────────────────────────────────────
SEG_FILE="selfie_segmentation.tflite"
if [ ! -f "$SEG_FILE" ]; then
  echo "⬇️  Downloading $SEG_FILE ..."
  curl -fL -o "$SEG_FILE" \
    "https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/1/selfie_segmenter.tflite"
  echo "✅ $SEG_FILE downloaded ($(du -sh "$SEG_FILE" | cut -f1))"
else
  echo "✅ $SEG_FILE already present — skipping"
fi

# ── Low-light enhancement ─────────────────────────────────────────────────────
LL_FILE="low_light_enhance.tflite"
if [ ! -f "$LL_FILE" ]; then
  echo "⬇️  Downloading $LL_FILE ..."
  # Zero-DCE Lite from TF Hub (5–6 MB)
  curl -fL -o "$LL_FILE" \
    "https://tfhub.dev/sayannath/lite-model/zero-dce/dr/1?lite-format=tflite" || {
      echo "⚠️  TF Hub download failed — trying alternate mirror ..."
      curl -fL -o "$LL_FILE" \
        "https://storage.googleapis.com/tfhub-lite-models/sayannath/lite-model/zero-dce/dr/1.tflite"
    }
  echo "✅ $LL_FILE downloaded ($(du -sh "$LL_FILE" | cut -f1))"
else
  echo "✅ $LL_FILE already present — skipping"
fi

# ── Voice Activity Detection ───────────────────────────────────────────────────
VAD_FILE="vad_lite.tflite"
if [ ! -f "$VAD_FILE" ]; then
  echo "⬇️  Downloading $VAD_FILE ..."
  curl -fL -o "$VAD_FILE" \
    "https://huggingface.co/snakers4/silero-vad/resolve/main/files/silero_vad.tflite" || {
      echo "⚠️  Could not download $VAD_FILE automatically."
      echo "    See README.md in this directory for manual download instructions."
      echo "    The app will still run without this file; VAD will be disabled."
    }
  if [ -f "$VAD_FILE" ]; then
    echo "✅ $VAD_FILE downloaded ($(du -sh "$VAD_FILE" | cut -f1))"
  fi
else
  echo "✅ $VAD_FILE already present — skipping"
fi

echo ""
echo "🎉 Done. Models in $MODELS_DIR:"
ls -lh "$MODELS_DIR"/*.tflite 2>/dev/null || echo "  (no .tflite files found — check download errors above)"
