#!/bin/bash

# Ollama Installation Script
# Installs Ollama and downloads required models

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define logging functions locally to avoid sourcing issues
log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

log_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

log_step() {
    echo -e "\n\033[0;34m═══════════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[0;34m  $1\033[0m"
    echo -e "\033[0;34m═══════════════════════════════════════════════════════════════\033[0m\n"
}

# Configuration file
CONFIG_FILE="$HOME/.local-ai-stack/config.env"

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Default values
OLLAMA_PORT=${OLLAMA_PORT:-11434}
FRONT_MODEL=${FRONT_MODEL:-"llama3:8b"}
BACK_MODEL=${BACK_MODEL:-"qwen2.5:14b-instruct"}
VISION_MODEL=${VISION_MODEL:-"qwen2.5-vl:7b-instruct"}
PULL_VISION=${PULL_VISION:-false}

# Check if Ollama is already installed
check_ollama_installed() {
    if command -v ollama &> /dev/null; then
        log_success "Ollama is already installed"
        return 0
    fi
    return 1
}

# Install Ollama
install_ollama() {
    log_info "Installing Ollama..."
    
    # Download and install Ollama
    curl -fsSL https://ollama.ai/install.sh | sh
    
    # Wait for Ollama to be available
    log_info "Waiting for Ollama to be ready..."
    sleep 5
    
    # Test installation
    if ! ollama --version &> /dev/null; then
        log_error "Ollama installation failed"
        exit 1
    fi
    
    log_success "Ollama installed successfully"
}

# Configure Ollama systemd service
configure_ollama_service() {
    log_info "Configuring Ollama systemd service..."
    
    # Create systemd service file
    sudo tee /etc/systemd/system/ollama.service > /dev/null << EOF
[Unit]
Description=Ollama Service
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
Environment=OLLAMA_HOST=127.0.0.1:$OLLAMA_PORT
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable ollama
    sudo systemctl start ollama
    
    # Wait for service to be ready
    log_info "Waiting for Ollama service to start..."
    sleep 10
    
    # Check service status
    if sudo systemctl is-active --quiet ollama; then
        log_success "Ollama service is running"
    else
        log_error "Ollama service failed to start"
        sudo systemctl status ollama
        exit 1
    fi
}

# Download models
download_models() {
    log_info "Downloading required models..."
    
    local models=("$FRONT_MODEL" "$BACK_MODEL")
    
    # Add vision model if requested
    if [[ "$PULL_VISION" == true ]] && [[ -n "$VISION_MODEL" ]]; then
        models+=("$VISION_MODEL")
    fi
    
    for model in "${models[@]}"; do
        log_info "Downloading model: $model"
        
        # Check if model already exists
        if ollama list | grep -q "$model"; then
            log_info "Model $model already exists, skipping download"
            continue
        fi
        
        # Download model
        if ollama pull "$model"; then
            log_success "Model $model downloaded successfully"
        else
            log_error "Failed to download model $model"
            exit 1
        fi
    done
    
    log_success "All required models downloaded"
}

# Test Ollama
test_ollama() {
    log_info "Testing Ollama installation..."
    
    # Test basic functionality
    if ! ollama list &> /dev/null; then
        log_error "Ollama list command failed"
        exit 1
    fi
    
    # Test API endpoint
    if ! curl -s "http://127.0.0.1:$OLLAMA_PORT/api/tags" &> /dev/null; then
        log_error "Ollama API endpoint not responding"
        exit 1
    fi
    
    # Test model loading
    log_info "Testing model loading with $FRONT_MODEL..."
    if ollama run "$FRONT_MODEL" "Hello, this is a test." &> /dev/null; then
        log_success "Model test completed successfully"
    else
        log_warning "Model test had issues (this may be normal for first run)"
    fi
    
    log_success "Ollama installation test passed"
}

# Configure environment
configure_environment() {
    log_info "Configuring environment..."
    
    # Add Ollama to PATH if not already there
    if ! grep -q "/usr/local/bin" "$HOME/.bashrc"; then
        echo 'export PATH="/usr/local/bin:$PATH"' >> "$HOME/.bashrc"
        log_info "Added Ollama to PATH in .bashrc"
    fi
    
    # Set OLLAMA_HOST environment variable
    if ! grep -q "OLLAMA_HOST" "$HOME/.bashrc"; then
        echo "export OLLAMA_HOST=127.0.0.1:$OLLAMA_PORT" >> "$HOME/.bashrc"
        log_info "Added OLLAMA_HOST to .bashrc"
    fi
    
    # Source the updated bashrc
    export PATH="/usr/local/bin:$PATH"
    export OLLAMA_HOST="127.0.0.1:$OLLAMA_PORT"
    
    log_success "Environment configured"
}

# Main function
main() {
    log_step "Ollama Installation"
    
    # Check if already installed
    if check_ollama_installed; then
        log_info "Ollama is already installed, checking service status..."
        
        # Check if service is running
        if sudo systemctl is-active --quiet ollama; then
            log_success "Ollama service is already running"
        else
            log_info "Starting Ollama service..."
            sudo systemctl start ollama
        fi
    else
        # Install Ollama
        install_ollama
    fi
    
    # Configure service
    configure_ollama_service
    
    # Download models
    download_models
    
    # Test installation
    test_ollama
    
    # Configure environment
    configure_environment
    
    log_success "Ollama installation completed successfully!"
    log_info "Ollama is running on port $OLLAMA_PORT"
    log_info "Models available: $(ollama list | grep -c '^[a-z]' || echo '0')"
}

# Run main function
main
