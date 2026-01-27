#!/bin/bash
set -e

# Install system dependencies
apt-get update
apt-get install -y python3-pip ffmpeg

# Install Python packages
pip3 install -r requirements.txt

# Download Piper voice model
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json

echo "Setup complete. Run: python3 workflow.py"
