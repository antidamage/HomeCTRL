#!/bin/bash

# STT Setup Script
# Sets up Speech-to-Text service using faster-whisper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../install.sh" 2>/dev/null || true

CONFIG_FILE="$HOME/.local-ai-stack/config.env"
source "$CONFIG_FILE"

STT_PORT=${STT_PORT:-5002}
STT_BACKEND=${STT_BACKEND:-"venv"}

setup_stt_venv() {
    log_info "Setting up STT service with virtual environment..."
    
    cd "$HOME/voice/stt"
    
    # Create virtual environment
    python3 -m venv venv
    source venv/bin/activate
    
    # Install requirements
    pip install fastapi uvicorn faster-whisper python-multipart
    
    # Create STT server
    cat > stt_server.py << EOF
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
import faster_whisper
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="STT Service", version="1.0.0")

# Initialize Whisper model
model = None

def get_model():
    global model
    if model is None:
        logger.info("Loading Whisper model...")
        model = faster_whisper.WhisperModel("base", device="auto", compute_type="auto")
        logger.info("Whisper model loaded")
    return model

@app.post("/transcribe")
async def transcribe_audio(audio: UploadFile = File(...)):
    """Transcribe uploaded audio file"""
    try:
        # Check file type
        if not audio.content_type.startswith("audio/"):
            raise HTTPException(status_code=400, detail="File must be an audio file")
        
        # Save uploaded file temporarily
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_file:
            content = await audio.read()
            temp_file.write(content)
            temp_file_path = temp_file.name
        
        try:
            # Transcribe
            model = get_model()
            segments, info = model.transcribe(temp_file_path)
            
            # Combine segments
            text = " ".join([segment.text for segment in segments])
            
            return JSONResponse(content={
                "text": text,
                "language": info.language,
                "language_probability": info.language_probability
            })
            
        finally:
            # Clean up temp file
            os.unlink(temp_file_path)
            
    except Exception as e:
        logger.error(f"Transcription error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "stt"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=${STT_PORT})
EOF

    # Create systemd service
    sudo tee /etc/systemd/system/stt.service > /dev/null << EOF
[Unit]
Description=STT Service
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$HOME/voice/stt
Environment=PATH=$HOME/voice/stt/venv/bin
ExecStart=$HOME/voice/stt/venv/bin/python stt_server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start service
    sudo systemctl daemon-reload
    sudo systemctl enable stt
    sudo systemctl start stt
    
    log_success "STT service started with virtual environment"
}

setup_stt_docker() {
    log_info "Setting up STT service with Docker..."
    
    cd "$HOME/voice/stt"
    
    # Create Dockerfile
    cat > Dockerfile << EOF
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \\
    ffmpeg \\
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

EXPOSE ${STT_PORT}

CMD ["uvicorn", "stt_server:app", "--host", "0.0.0.0", "--port", "${STT_PORT}"]
EOF

    # Create requirements.txt
    cat > requirements.txt << EOF
fastapi==0.104.1
uvicorn[standard]==0.24.0
faster-whisper==0.10.0
python-multipart==0.0.6
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << EOF
version: '3.8'
services:
  stt:
    build: .
    container_name: stt-service
    restart: unless-stopped
    network_mode: host
    ports:
      - "127.0.0.1:${STT_PORT}:${STT_PORT}"
    volumes:
      - ./data:/app/data
EOF

    # Build and start
    docker compose up -d --build
    
    log_success "STT service started with Docker"
}

main() {
    log_step "Setting up Speech-to-Text Service"
    
    if [[ "$STT_BACKEND" == "docker" ]]; then
        setup_stt_docker
    else
        setup_stt_venv
    fi
    
    log_info "STT service running on port $STT_PORT"
}

main
