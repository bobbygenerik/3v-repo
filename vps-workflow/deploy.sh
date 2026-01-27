#!/bin/bash
set -e

cd /home/ubuntu/projects/3v-repo/vps-workflow

# Install dependencies
sudo apt-get update
sudo apt-get install -y python3-pip ffmpeg
pip3 install flask faster-whisper ctranslate2 transformers torch piper-tts requests

# Download Piper voice
wget -q https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx
wget -q https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json

# Setup systemd service
sudo cp translation.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable translation
sudo systemctl start translation

# Open firewall
sudo ufw allow 5000

echo "Translation service running on port 5000"
