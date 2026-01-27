#!/usr/bin/env python3
from faster_whisper import WhisperModel
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM
import subprocess

class AudioWorkflow:
    def __init__(self):
        self.whisper = WhisperModel("base", device="cpu", compute_type="int8")
        self.tokenizer = AutoTokenizer.from_pretrained("facebook/nllb-200-distilled-600M")
        self.translator = AutoModelForSeq2SeqLM.from_pretrained("facebook/nllb-200-distilled-600M")
    
    def transcribe(self, audio_path):
        segments, _ = self.whisper.transcribe(audio_path)
        return " ".join([seg.text for seg in segments])
    
    def translate(self, text, src_lang="eng_Latn", tgt_lang="spa_Latn"):
        self.tokenizer.src_lang = src_lang
        inputs = self.tokenizer(text, return_tensors="pt")
        tokens = self.translator.generate(**inputs, forced_bos_token_id=self.tokenizer.lang_code_to_id[tgt_lang])
        return self.tokenizer.batch_decode(tokens, skip_special_tokens=True)[0]
    
    def speak(self, text, output_path="output.wav", voice="en_US-lessac-medium"):
        subprocess.run(["piper", "--model", voice, "--output_file", output_path], input=text.encode())
    
    def process(self, audio_path, src_lang="eng_Latn", tgt_lang="spa_Latn"):
        text = self.transcribe(audio_path)
        translated = self.translate(text, src_lang, tgt_lang)
        self.speak(translated)
        return translated

if __name__ == "__main__":
    workflow = AudioWorkflow()
    result = workflow.process("input.wav")
    print(result)
