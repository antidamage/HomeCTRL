#!/bin/bash

# Open WebUI Setup Script
# Sets up Open WebUI with Docker

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

WEBUI_PORT=${WEBUI_PORT:-8080}
OLLAMA_PORT=${OLLAMA_PORT:-11434}
ROUTER_PORT=${ROUTER_PORT:-1338}

setup_openwebui() {
    log_step "Setting up Open WebUI"
    
    cd "$HOME/ollama-webui"
    
    # Create docker-compose.yml
    cat > docker-compose.yml << EOF
version: '3.8'
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    network_mode: host
    environment:
      - OLLAMA_BASE_URL=http://127.0.0.1:${OLLAMA_PORT}
      - OPENAI_API_BASE_URL=http://127.0.0.1:${ROUTER_PORT}/v1
      - OPENAI_API_KEY=EMPTY
      - WEBUI_SECRET_KEY=your-secret-key-here
      - DEFAULT_MODELS=router-escalate
      - ENABLE_SIGNUP=false
      - ENABLE_LOGIN_FORM=true
    volumes:
      - ./data:/app/backend/data
      - ./user:/app/backend/user
    ports:
      - "127.0.0.1:${WEBUI_PORT}:8080"
EOF

    # Start service
    docker compose up -d
    
    log_success "Open WebUI started on port $WEBUI_PORT"
}

main() {
    setup_openwebui
}

main
