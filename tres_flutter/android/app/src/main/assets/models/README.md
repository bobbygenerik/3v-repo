# LiteRT Model Assets

Place the `.tflite` model files in this directory before building.
A convenience download script is provided at `scripts/download_models.sh`.

---

## Required models

| File | Feature | Size | Source |
|------|---------|------|--------|
| `selfie_segmentation.tflite` | Background blur | ~1 MB | MediaPipe / TF Hub |
| `low_light_enhance.tflite` | Low-light video sharpening | ~5 MB | TF Hub (Zero-DCE or MIRNet-V2 Lite) |
| `vad_lite.tflite` | Voice Activity Detection | ~1 MB | TF Hub (silero-vad converted) |

> `sharpening` uses a built-in convolution kernel — no model file needed.

---

## Download instructions

### selfie_segmentation.tflite
MediaPipe's selfie segmentation landscape model (fastest, 256×144 input):

```
wget -O selfie_segmentation.tflite \
  "https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/1/selfie_segmenter.tflite"
```

Or download from TF Hub:
```
# Python
import tensorflow_hub as hub
import urllib.request
urllib.request.urlretrieve(
    "https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/1/selfie_segmenter.tflite",
    "selfie_segmentation.tflite"
)
```

### low_light_enhance.tflite
Zero-DCE Lite (lightweight zero-reference low-light enhancement):
```
# Clone and convert
git clone https://github.com/soumik12345/Zero-DCE
# OR download pre-converted from:
# https://tfhub.dev/sayannath/lite-model/zero-dce/dr/1?lite-format=tflite
wget -O low_light_enhance.tflite \
  "https://tfhub.dev/sayannath/lite-model/zero-dce/dr/1?lite-format=tflite"
```

### vad_lite.tflite
Silero VAD converted to TFLite:
```
# Download from HuggingFace
wget -O vad_lite.tflite \
  "https://huggingface.co/snakers4/silero-vad/resolve/main/files/silero_vad.tflite"
```

---

## Model I/O specs (used by LiteRTVideoProcessor.kt)

### selfie_segmentation.tflite
- **Input**: `[1, 144, 256, 3]` float32 RGB, values in [0, 1]
- **Output**: `[1, 144, 256, 1]` float32 confidence mask (1 = person, 0 = background)

### low_light_enhance.tflite
- **Input**: `[1, 400, 400, 3]` float32 RGB, values in [0, 1]
- **Output**: `[1, 400, 400, 3]` float32 enhanced RGB, values in [0, 1]

### vad_lite.tflite
- **Input**: `[512]` float32 PCM audio at 16 kHz mono
- **Output**: `[1]` float32 speech confidence (> 0.6 = speech detected)

---

## Notes

- Models are **not** committed to the repository to keep APK size manageable.
- The app gracefully disables each feature if its model file is missing (warns in logcat).
- For CI builds, add model download steps to `codemagic.yaml` before the Flutter build step.
- GPU delegate is used when available (most Android 8+ devices); falls back to CPU threads.
