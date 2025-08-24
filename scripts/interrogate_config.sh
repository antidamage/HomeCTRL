#!/bin/bash

# Configuration Interrogation Script
# Prompts user for all necessary configuration values

set -euo pipefail

# Source the main installer functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../install.sh" 2>/dev/null || true

# Configuration file
CONFIG_FILE="$HOME/.local-ai-stack/config.env"

# Default values
SERVER_IP=""
DOMAIN_UI=""
DOMAIN_API=""
OLLAMA_PORT=11434
WEBUI_PORT=8080
ROUTER_PORT=1338
STT_PORT=5002
TTS_PORT=5003
TAVILY_KEY=""
FRONT_MODEL="llama3:8b"
BACK_MODEL="qwen2.5:14b-instruct"
VISION_MODEL="qwen2.5-vl:7b-instruct"
STT_BACKEND="venv"
TTS_BACKEND="venv"
PULL_VISION=false

# Load existing config if available
if [[ -f "$CONFIG_FILE" ]]; then
    log_info "Loading existing configuration..."
    source "$CONFIG_FILE"
fi

# Get server IP address
get_server_ip() {
    if [[ -z "$SERVER_IP" ]]; then
        # Try to detect automatically
        local detected_ip
        detected_ip=$(hostname -I | awk '{print $1}' | head -1)
        
        if [[ -n "$detected_ip" ]]; then
            log_info "Detected server IP: $detected_ip"
            read -p "Use this IP address? (Y/n): " -r
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                read -p "Enter server IP address: " SERVER_IP
            else
                SERVER_IP="$detected_ip"
            fi
        else
            read -p "Enter server IP address: " SERVER_IP
        fi
    fi
    
    # Validate IP format
    if [[ ! $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid IP address format: $SERVER_IP"
        exit 1
    fi
}

# Get domain configuration
get_domain_config() {
    log_info "Domain Configuration (optional - press Enter to skip)"
    log_info "If you have domain names, we can set up HTTPS with Let's Encrypt"
    
    read -p "Enter domain for WebUI (e.g., ai.example.com): " DOMAIN_UI
    read -p "Enter domain for API (e.g., api.example.com): " DOMAIN_API
    
    if [[ -n "$DOMAIN_UI" ]] || [[ -n "$DOMAIN_API" ]]; then
        log_info "TLS will be configured for the provided domains"
    else
        log_info "No domains provided - HTTP-only mode will be used"
    fi
}

# Get port configuration
get_port_config() {
    log_info "Port Configuration"
    log_info "Default ports are recommended for most installations"
    
    read -p "Use default ports? (Y/n): " -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        read -p "Ollama port [$OLLAMA_PORT]: " input
        [[ -n "$input" ]] && OLLAMA_PORT="$input"
        
        read -p "WebUI port [$WEBUI_PORT]: " input
        [[ -n "$input" ]] && WEBUI_PORT="$input"
        
        read -p "Router port [$ROUTER_PORT]: " input
        [[ -n "$input" ]] && ROUTER_PORT="$input"
        
        read -p "STT port [$STT_PORT]: " input
        [[ -n "$input" ]] && STT_PORT="$input"
        
        read -p "TTS port [$TTS_PORT]: " input
        [[ -n "$input" ]] && TTS_PORT="$input"
    fi
}

# Get API keys
get_api_keys() {
    log_info "API Keys Configuration"
    
    if [[ -z "$TAVILY_KEY" ]]; then
        log_info "Tavily API Key (optional - for web search functionality)"
        log_info "Get your free key at: https://tavily.com"
        read -p "Enter Tavily API key (or press Enter to skip): " TAVILY_KEY
    fi
    
    if [[ -n "$TAVILY_KEY" ]]; then
        log_success "Tavily API key configured for web search"
    else
        log_warning "No Tavily API key provided - web search will be disabled"
    fi
}

# Get model configuration
get_model_config() {
    log_info "Model Configuration"
    
    log_info "Available front models (fast/planner):"
    log_info "  1. llama3:8b (default, fast, good for simple tasks)"
    log_info "  2. deepseek-coder:6.7b-instruct (good for coding)"
    
    read -p "Select front model (1-2) [1]: " choice
    case $choice in
        2)
            FRONT_MODEL="deepseek-coder:6.7b-instruct"
            ;;
        *)
            FRONT_MODEL="llama3:8b"
            ;;
    esac
    
    log_info "Available back models (heavy/solver):"
    log_info "  1. qwen2.5:14b-instruct (default, balanced performance)"
    log_info "  2. llama3:8b (faster, smaller)"
    
    read -p "Select back model (1-2) [1]: " choice
    case $choice in
        2)
            BACK_MODEL="llama3:8b"
            ;;
        *)
            BACK_MODEL="qwen2.5:14b-instruct"
            ;;
    esac
    
    log_info "Vision models (optional - for image understanding):"
    log_info "  1. qwen2.5-vl:7b-instruct (recommended)"
    log_info "  2. llava:13b (larger, potentially better)"
    log_info "  3. Skip vision models"
    
    read -p "Select vision model (1-3) [3]: " choice
    case $choice in
        1)
            VISION_MODEL="qwen2.5-vl:7b-instruct"
            PULL_VISION=true
            ;;
        2)
            VISION_MODEL="llava:13b"
            PULL_VISION=true
            ;;
        *)
            VISION_MODEL=""
            PULL_VISION=false
            ;;
    esac
}

# Get backend configuration
get_backend_config() {
    log_info "Backend Configuration"
    log_info "Choose between virtual environments (venv) or Docker for STT/TTS services"
    
    read -p "STT backend - venv (default) or docker? [venv]: " input
    if [[ -n "$input" ]]; then
        if [[ "$input" == "docker" ]]; then
            STT_BACKEND="docker"
        else
            STT_BACKEND="venv"
        fi
    fi
    
    read -p "TTS backend - venv (default) or docker? [venv]: " input
    if [[ -n "$input" ]]; then
        if [[ "$input" == "docker" ]]; then
            TTS_BACKEND="docker"
        else
            TTS_BACKEND="venv"
        fi
    fi
    
    log_info "STT backend: $STT_BACKEND"
    log_info "TTS backend: $TTS_BACKEND"
}

# Validate configuration
validate_config() {
    log_info "Validating configuration..."
    
    # Check for required values
    if [[ -z "$SERVER_IP" ]]; then
        log_error "Server IP is required"
        exit 1
    fi
    
    # Check port conflicts
    local ports=("$OLLAMA_PORT" "$WEBUI_PORT" "$ROUTER_PORT" "$STT_PORT" "$TTS_PORT")
    local unique_ports=($(printf '%s\n' "${ports[@]}" | sort -u))
    
    if [[ ${#ports[@]} -ne ${#unique_ports[@]} ]]; then
        log_error "Port conflicts detected - all services must use different ports"
        exit 1
    fi
    
    # Check if ports are in use
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_warning "Port $port appears to be in use"
            read -p "Continue anyway? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    done
    
    log_success "Configuration validation passed"
}

# Display configuration summary
show_config_summary() {
    log_step "Configuration Summary"
    
    cat << EOF
Server Configuration:
  IP Address: $SERVER_IP
  WebUI Domain: ${DOMAIN_UI:-"Not configured"}
  API Domain: ${DOMAIN_API:-"Not configured"}

Service Ports:
  Ollama: $OLLAMA_PORT
  WebUI: $WEBUI_PORT
  Router: $ROUTER_PORT
  STT: $STT_PORT
  TTS: $TTS_PORT

Model Selection:
  Front Model: $FRONT_MODEL
  Back Model: $BACK_MODEL
  Vision Model: ${VISION_MODEL:-"Not configured"}
  Pull Vision: $PULL_VISION

Backend Selection:
  STT: $STT_BACKEND
  TTS: $TTS_BACKEND

API Keys:
  Tavily: ${TAVILY_KEY:+Configured}${TAVILY_KEY:-"Not configured"}
EOF

    read -p "Proceed with this configuration? (Y/n): " -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Configuration cancelled. Re-run installer to try again."
        exit 1
    fi
}

# Main function
main() {
    log_step "Configuration Setup"
    log_info "Setting up your local AI stack configuration..."
    
    # Get configuration values
    get_server_ip
    get_domain_config
    get_port_config
    get_api_keys
    get_model_config
    get_backend_config
    
    # Validate configuration
    validate_config
    
    # Show summary and confirm
    show_config_summary
    
    # Save configuration
    save_config
    
    log_success "Configuration saved successfully!"
    log_info "You can now proceed with the installation."
}

# Run main function
main
