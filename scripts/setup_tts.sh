#!/bin/bash

# TTS Setup Script
# Sets up Text-to-Speech service using Piper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define logging functions locally to avoid sourcing issues
log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

log_step() {
    echo -e "\n\033[0;34m═══════════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[0;34m  $1\033[0m"
    echo -e "\033[0;34m═══════════════════════════════════════════════════════════════\033[0m\n"
}

CONFIG_FILE="$HOME/.local-ai-stack/config.env"
source "$CONFIG_FILE"

TTS_PORT=${TTS_PORT:-5003}
TTS_BACKEND=${TTS_BACKEND:-"venv"}

setup_tts_venv() {
    log_info "Setting up TTS service with virtual environment..."
    
    cd "$HOME/voice/tts"
    
    # Create virtual environment
    python3 -m venv venv
    source venv/bin/activate
    
    # Install requirements
    pip install fastapi uvicorn piper-tts python-multipart
    
    # Download voice model
    mkdir -p voices
    cd voices
    wget -O en_US-amy-low.onnx https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/low/en_US-amy-low.onnx
    wget -O en_US-amy-low.onnx.json https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/low/en_US-amy-low.onnx.json
    cd ..
    
    # Create TTS server
    cat > tts_server.py << EOF
from fastapi import FastAPI, Query, HTTPException
from fastapi.responses import Response
import piper
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="TTS Service", version="1.0.0")

# Initialize Piper TTS
tts = None

def get_tts():
    global tts
    if tts is None:
        logger.info("Loading Piper TTS model...")
        model_path = os.path.join("voices", "en_US-amy-low.onnx")
        config_path = os.path.join("voices", "en_US-amy-low.onnx.json")
        tts = piper.PiperVoice.load(model_path, config_path)
        logger.info("Piper TTS model loaded")
    return tts

@app.get("/speak")
async def speak_text(q: str = Query(..., description="Text to speak")):
    """Convert text to speech"""
    try:
        if not q or len(q.strip()) == 0:
            raise HTTPException(status_code=400, detail="Text parameter is required")
        
        # Limit text length
        if len(q) > 1000:
            raise HTTPException(status_code=400, detail="Text too long (max 1000 characters)")
        
        # Get TTS instance
        tts_instance = get_tts()
        
        # Generate speech
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_file:
            tts_instance.synthesize(q, temp_file)
            temp_file_path = temp_file.name
        
        try:
            # Read generated audio
            with open(temp_file_path, "rb") as audio_file:
                audio_data = audio_file.read()
            
            return Response(
                content=audio_data,
                media_type="audio/wav",
                headers={"Content-Disposition": f"attachment; filename=speech.wav"}
            )
            
        finally:
            # Clean up temp file
            os.unlink(temp_file_path)
            
    except Exception as e:
        logger.error(f"TTS error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "tts"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=${TTS_PORT})
EOF

    # Create systemd service
    sudo tee /etc/systemd/system/tts.service > /dev/null << EOF
[Unit]
Description=TTS Service
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$HOME/voice/tts
Environment=PATH=$HOME/voice/tts/venv/bin
ExecStart=$HOME/voice/tts/venv/bin/python tts_server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start service
    sudo systemctl daemon-reload
    sudo systemctl enable tts
    sudo systemctl start tts
    
    log_success "TTS service started with virtual environment"
}

setup_tts_docker() {
    log_info "Setting up TTS service with Docker..."
    
    cd "$HOME/voice/tts"
    
    # Create Dockerfile
    cat > Dockerfile << EOF
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \\
    wget \\
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

# Download voice model
RUN mkdir -p voices && cd voices \\
    && wget -O en_US-amy-low.onnx https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/low/en_US-amy-low.onnx \\
    && wget -O en_US-amy-low.onnx.json https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/low/en_US-amy-low.onnx.json

EXPOSE ${TTS_PORT}

CMD ["uvicorn", "tts_server:app", "--host", "0.0.0.0", "--port", "${TTS_PORT}"]
EOF

    # Create requirements.txt
    cat > requirements.txt << EOF
fastapi==0.104.1
uvicorn[standard]==0.24.0
piper-tts==1.2.0
python-multipart==0.0.6
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << EOF
version: '3.8'
services:
  tts:
    build: .
    container_name: tts-service
    restart: unless-stopped
    network_mode: host
    ports:
      - "127.0.0.1:${TTS_PORT}:${TTS_PORT}"
    volumes:
      - ./data:/app/data
EOF

    # Build and start
    docker compose up -d --build
    
    log_success "TTS service started with Docker"
}

main() {
    log_step "Setting up Text-to-Speech Service"
    
    if [[ "$TTS_BACKEND" == "docker" ]]; then
        setup_tts_docker
    else
        setup_tts_venv
    fi
    
    log_info "TTS service running on port $TTS_PORT"
}

main
