from flask import Flask, request, jsonify
from faster_whisper import WhisperModel
from transformers import AutoModelForSeq2SeqLM, NllbTokenizer
import requests
import uuid
import os

app = Flask(__name__)

whisper = WhisperModel("base", device="cpu", compute_type="int8")
tokenizer = NllbTokenizer.from_pretrained("facebook/nllb-200-distilled-600M")
translator = AutoModelForSeq2SeqLM.from_pretrained("facebook/nllb-200-distilled-600M")

@app.route("/translate", methods=["POST"])
def translate():
    data = request.json
    audio_url = data["audioUrl"]
    src_lang = data.get("srcLang", "eng_Latn")
    tgt_lang = data.get("tgtLang", "spa_Latn")
    
    audio_id = str(uuid.uuid4())
    input_path = f"/tmp/{audio_id}_input.wav"
    
    r = requests.get(audio_url)
    with open(input_path, "wb") as f:
        f.write(r.content)
    
    segments, _ = whisper.transcribe(input_path)
    text = " ".join([seg.text for seg in segments])
    
    tokenizer.src_lang = src_lang
    inputs = tokenizer(text, return_tensors="pt")
    tokens = translator.generate(**inputs, forced_bos_token_id=tokenizer.lang_code_to_id[tgt_lang])
    translated = tokenizer.batch_decode(tokens, skip_special_tokens=True)[0]
    
    os.remove(input_path)
    return jsonify({"text": translated})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
