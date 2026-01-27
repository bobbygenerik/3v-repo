# VPS Translation Workflow

Real-time audio translation for video calls using Faster Whisper, NLLB, and Piper TTS.

## Setup

1. **Deploy to VPS:**
```bash
chmod +x deploy.sh
./deploy.sh
```

2. **Update Functions .env:**
```bash
VPS_TRANSLATION_URL=http://YOUR_VPS_IP:5000
```

3. **Deploy Cloud Function:**
```bash
cd ../functions
firebase deploy --only functions:translateAudio
```

## Usage in Flutter

```dart
final translation = TranslationService();
final result = await translation.translateAudio(
  audioUrl,
  srcLang: 'eng_Latn',
  tgtLang: 'spa_Latn'
);
// result['translatedAudioUrl'] - play this
// result['text'] - display this
```

## Language Codes

- English: `eng_Latn`
- Spanish: `spa_Latn`
- French: `fra_Latn`
- German: `deu_Latn`
- Chinese: `zho_Hans`
- Arabic: `arb_Arab`

Full list: https://github.com/facebookresearch/flores/blob/main/flores200/README.md#languages-in-flores-200
