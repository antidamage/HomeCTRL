#!/bin/bash

# Local AI Stack Installer
# A comprehensive installer for setting up a full local AI rig

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration file
CONFIG_DIR="$HOME/.local-ai-stack"
CONFIG_FILE="$CONFIG_DIR/config.env"

# Default values
PULL_VISION=false
STT_BACKEND="venv"
TTS_BACKEND="venv"
FRONT_MODEL="llama3:8b"
BACK_MODEL="qwen2.5:14b-instruct"
ROUTER_PORT=1338
WEBUI_PORT=8080
STT_PORT=5002
TTS_PORT=5003
DOMAIN_UI=""
DOMAIN_API=""
TAVILY_KEY=""
NONINTERACTIVE=false
RECONFIGURE=false

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

# Help function
show_help() {
    cat << EOF
Local AI Stack Installer

Usage: $0 [OPTIONS]

OPTIONS:
    --pull-vision              Also pull vision-capable models
    --stt-backend=TYPE         STT backend: venv (default) or docker
    --tts-backend=TYPE         TTS backend: venv (default) or docker
    --front-model=MODEL        Front model for router (default: llama3:8b)
    --back-model=MODEL         Back model for router (default: qwen2.5:14b-instruct)
    --router-port=PORT         Router port (default: 1338)
    --webui-port=PORT          WebUI port (default: 8080)
    --stt-port=PORT            STT port (default: 5002)
    --tts-port=PORT            TTS port (default: 5003)
    --domain-ui=DOMAIN         Domain for WebUI (e.g., ai.example.com)
    --domain-api=DOMAIN        Router API domain (auto-generated from WebUI domain)
    --tavily-key=KEY           Tavily API key for web search
    --noninteractive           Use existing config without prompts
    --reconfigure              Force reconfiguration
    -h, --help                 Show this help message

EXAMPLES:
    $0                                    # Interactive installation
    $0 --noninteractive                   # Use existing config
    $0 --reconfigure                      # Force reconfiguration
    $0 --pull-vision --stt-backend=docker # With vision models and Docker STT
    $0 --domain-ui=ai.example.com        # WebUI domain (Router API auto-generated)

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --pull-vision)
                PULL_VISION=true
                shift
                ;;
            --stt-backend=*)
                STT_BACKEND="${1#*=}"
                shift
                ;;
            --tts-backend=*)
                TTS_BACKEND="${1#*=}"
                shift
                ;;
            --front-model=*)
                FRONT_MODEL="${1#*=}"
                shift
                ;;
            --back-model=*)
                BACK_MODEL="${1#*=}"
                shift
                ;;
            --router-port=*)
                ROUTER_PORT="${1#*=}"
                shift
                ;;
            --webui-port=*)
                WEBUI_PORT="${1#*=}"
                shift
                ;;
            --stt-port=*)
                STT_PORT="${1#*=}"
                shift
                ;;
            --tts-port=*)
                TTS_PORT="${1#*=}"
                shift
                ;;
            --domain-ui=*)
                DOMAIN_UI="${1#*=}"
                shift
                ;;
            --domain-api=*)
                DOMAIN_API="${1#*=}"
                shift
                ;;
            --tavily-key=*)
                TAVILY_KEY="${1#*=}"
                shift
                ;;
            --noninteractive)
                NONINTERACTIVE=true
                shift
                ;;
            --reconfigure)
                RECONFIGURE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root. Please run as a regular user with sudo access."
        exit 1
    fi
}

# Check script permissions and fix if needed
check_script_permissions() {
    local script_dir="$SCRIPT_DIR/scripts"
    local scripts=(
        "interrogate_config.sh"
        "check_prereqs.sh"
        "install_ollama.sh"
        "setup_openwebui.sh"
        "setup_router.sh"
        "setup_stt.sh"
        "setup_tts.sh"
        "setup_nginx.sh"
        "health_checks.sh"
    )
    
    local needs_fix=false
    
    for script in "${scripts[@]}"; do
        if [[ ! -x "$script_dir/$script" ]]; then
            needs_fix=true
            break
        fi
    done
    
    if [[ "$needs_fix" == true ]]; then
        log_warning "Script permissions need to be fixed..."
        log_info "Attempting to fix script permissions..."
        
        if chmod +x "$script_dir"/*.sh 2>/dev/null; then
            log_success "Script permissions fixed successfully"
        else
            log_error "Failed to fix script permissions automatically"
            log_info "Please run the following command manually:"
            log_info "  chmod +x scripts/*.sh"
            log_info "Then run the installer again:"
            log_info "  ./install.sh"
            exit 1
        fi
    fi
}

# Check Ubuntu version
check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "This installer is designed exclusively for Ubuntu Server 22.04 LTS"
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]] || [[ "$VERSION_ID" != "22.04" ]]; then
        log_error "This installer is designed exclusively for Ubuntu Server 22.04 LTS"
        log_error "You're running: $ID $VERSION_ID"
        log_error ""
        log_error "To use this installer, you must:"
        log_error "1. Install Ubuntu Server 22.04 LTS, OR"
        log_error "2. Install WSL2 with Ubuntu 22.04 LTS on Windows"
        log_error ""
        log_error "For WSL2 installation: https://docs.microsoft.com/en-us/windows/wsl/install"
        exit 1
    fi
    
    log_success "Ubuntu 22.04 LTS detected ✓"
}

# Create configuration directory
create_config_dir() {
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR"
        log_success "Created configuration directory: $CONFIG_DIR"
    fi
}

# Load existing configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]] && [[ "$NONINTERACTIVE" == true ]]; then
        log_info "Loading existing configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
        log_success "Configuration loaded successfully"
    fi
}

# Save configuration
save_config() {
    cat > "$CONFIG_FILE" << EOF
# Local AI Stack Configuration
# Generated on $(date)

# Server Configuration
SERVER_IP=$SERVER_IP
DOMAIN_UI=$DOMAIN_UI
DOMAIN_API=$DOMAIN_API

# Service Ports
OLLAMA_PORT=$OLLAMA_PORT
WEBUI_PORT=$WEBUI_PORT
ROUTER_PORT=$ROUTER_PORT
STT_PORT=$STT_PORT
TTS_PORT=$TTS_PORT

# API Keys
TAVILY_API_KEY=$TAVILY_KEY

# Model Selection
FRONT_MODEL=$FRONT_MODEL
BACK_MODEL=$BACK_MODEL
VISION_MODEL=$VISION_MODEL

# Backend Selection
STT_BACKEND=$STT_BACKEND
TTS_BACKEND=$TTS_BACKEND

# Installation Flags
PULL_VISION=$PULL_VISION
EOF

    log_success "Configuration saved to $CONFIG_FILE"
}

# Main installation function
main() {
    log_step "Local AI Stack Installer"
    log_info "Starting installation process..."
    log_info "Note: This installer will run as a regular user and use sudo when needed"
    log_info "Do NOT run this script with sudo - it will handle elevated privileges automatically"
    
    # Parse arguments
    parse_args "$@"
    
    # Pre-flight checks
    check_root
    check_ubuntu
    check_script_permissions
    
    # Create config directory
    create_config_dir
    
    # Load existing config if non-interactive
    if [[ "$NONINTERACTIVE" == true ]]; then
        load_config
    fi
    
    # Run configuration interrogation
    if [[ "$RECONFIGURE" == true ]] || [[ "$NONINTERACTIVE" == false ]]; then
        log_step "Configuration Setup"
        "$SCRIPT_DIR/scripts/interrogate_config.sh"
    fi
    
    # Load final configuration
    source "$CONFIG_FILE"
    
    # Install prerequisites
    log_step "Installing Prerequisites"
    "$SCRIPT_DIR/scripts/check_prereqs.sh"
    
    # Install Ollama
    log_step "Installing Ollama"
    "$SCRIPT_DIR/scripts/install_ollama.sh"
    
    # Setup Open WebUI
    log_step "Setting up Open WebUI"
    "$SCRIPT_DIR/scripts/setup_openwebui.sh"
    
    # Setup Router
    log_step "Setting up Router"
    "$SCRIPT_DIR/scripts/setup_router.sh"
    
    # Setup STT
    log_step "Setting up Speech-to-Text"
    "$SCRIPT_DIR/scripts/setup_stt.sh"
    
    # Setup TTS
    log_step "Setting up Text-to-Speech"
    "$SCRIPT_DIR/scripts/setup_tts.sh"
    
    # Setup Nginx
    log_step "Setting up Nginx Proxy"
    "$SCRIPT_DIR/scripts/setup_nginx.sh"
    
    # Health checks
    log_step "Running Health Checks"
    "$SCRIPT_DIR/scripts/health_checks.sh"
    
    # Final summary
    log_step "Installation Complete!"
    log_success "Your local AI stack is now running!"
    log_info ""
    
    if [[ -n "${DOMAIN_UI:-}" ]] && [[ -n "${DOMAIN_API:-}" ]]; then
        log_info "🌐 Domain Access (HTTPS):"
        log_info "  WebUI: https://$DOMAIN_UI"
        log_info "  Router API: https://$DOMAIN_API/v1"
        log_info "  STT Service: https://$DOMAIN_UI/stt/"
        log_info "  TTS Service: https://$DOMAIN_UI/tts/"
        log_info ""
        log_info "🏠 Local Access (HTTP):"
        log_info "  WebUI: http://localhost"
        log_info "  Router API: http://localhost/api/"
        log_info "  STT Service: http://localhost/stt/"
        log_info "  TTS Service: http://localhost/tts/"
    else
        log_info "🏠 Local Access (HTTP):"
        log_info "  WebUI: http://localhost"
        log_info "  Router API: http://localhost/api/"
        log_info "  STT Service: http://localhost/stt/"
        log_info "  TTS Service: http://localhost/tts/"
        log_info ""
        log_info "  Direct Port Access:"
        log_info "    WebUI: http://localhost:$WEBUI_PORT"
        log_info "    Router API: http://localhost:$ROUTER_PORT/v1"
        log_info "    STT Service: http://localhost:$STT_PORT"
        log_info "    TTS Service: http://localhost:$TTS_PORT"
    fi
    
    log_info ""
    log_info "🚀 Quick Start:"
    log_info "  1. Open your browser and go to: http://localhost"
    log_info "  2. Try chatting with the 'router-escalate' model"
    log_info "  3. Test STT/TTS endpoints if needed"
    log_info "  4. Enjoy your local AI stack!"
    log_info ""
    log_info "📊 Run health checks: ./scripts/health_checks.sh"
    log_info "📝 View logs: make logs"
    log_info "🔄 Manage services: make up/down/status"
    log_info "🗑️  Uninstall: ./cleanup.sh"
    log_info ""
    log_info "Configuration saved to: $CONFIG_FILE"
    log_info "Re-run installer with --noninteractive to use existing config"
}

# Run main function with all arguments
main "$@"
