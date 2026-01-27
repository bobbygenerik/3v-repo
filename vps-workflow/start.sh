#!/bin/bash
cd /home/ubuntu/projects/3v-repo/vps-workflow
source venv/bin/activate

echo "Downloading models..."
python3 -c "
from faster_whisper import WhisperModel
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM

print('Loading Whisper...')
WhisperModel('base', device='cpu', compute_type='int8')

print('Loading NLLB tokenizer...')
AutoTokenizer.from_pretrained('facebook/nllb-200-distilled-600M')

print('Loading NLLB model...')
AutoModelForSeq2SeqLM.from_pretrained('facebook/nllb-200-distilled-600M')

print('All models loaded!')
"

echo "Starting server..."
python3 server.py
