#!/bin/bash

# Local AI Stack Cleanup Script
# Removes all services and optionally data volumes

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration file
CONFIG_FILE="$HOME/.local-ai-stack/config.env"

# Load configuration if available
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Default values
WEBUI_PORT=${WEBUI_PORT:-8080}
ROUTER_PORT=${ROUTER_PORT:-1338}
STT_PORT=${STT_PORT:-5002}
TTS_PORT=${TTS_PORT:-5003}

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

# Stop and remove Docker services
cleanup_docker_services() {
    log_step "Cleaning up Docker Services"
    
    # Stop and remove Open WebUI
    if [[ -d "$HOME/ollama-webui" ]]; then
        log_info "Stopping Open WebUI..."
        cd "$HOME/ollama-webui"
        docker compose down -v 2>/dev/null || true
        log_success "Open WebUI stopped and removed"
    fi
    
    # Stop and remove Router
    if [[ -d "$HOME/llama-router" ]]; then
        log_info "Stopping Router service..."
        cd "$HOME/llama-router"
        docker compose down -v 2>/dev/null || true
        log_success "Router service stopped and removed"
    fi
    
    # Stop and remove STT Docker service if exists
    if [[ -d "$HOME/voice/stt" ]] && [[ "${STT_BACKEND:-venv}" == "docker" ]]; then
        log_info "Stopping STT Docker service..."
        cd "$HOME/voice/stt"
        docker compose down -v 2>/dev/null || true
        log_success "STT Docker service stopped and removed"
    fi
    
    # Stop and remove TTS Docker service if exists
    if [[ -d "$HOME/voice/tts" ]] && [[ "${TTS_BACKEND:-venv}" == "docker" ]]; then
        log_info "Stopping TTS Docker service..."
        cd "$HOME/voice/tts"
        docker compose down -v 2>/dev/null || true
        log_success "TTS Docker service stopped and removed"
    fi
    
    # Clean up Docker system
    log_info "Cleaning up Docker system..."
    docker system prune -f 2>/dev/null || true
    log_success "Docker system cleaned up"
}

# Stop and remove systemd services
cleanup_systemd_services() {
    log_step "Cleaning up Systemd Services"
    
    # Stop and disable Ollama
    if sudo systemctl is-active --quiet ollama 2>/dev/null; then
        log_info "Stopping Ollama service..."
        sudo systemctl stop ollama
        sudo systemctl disable ollama
        log_success "Ollama service stopped and disabled"
    fi
    
    # Stop and disable STT service
    if sudo systemctl is-active --quiet stt 2>/dev/null; then
        log_info "Stopping STT service..."
        sudo systemctl stop stt
        sudo systemctl disable stt
        log_success "STT service stopped and disabled"
    fi
    
    # Stop and disable TTS service
    if sudo systemctl is-active --quiet tts 2>/dev/null; then
        log_info "Stopping TTS service..."
        sudo systemctl stop tts
        sudo systemctl disable tts
        log_success "TTS service stopped and disabled"
    fi
    
    # Stop and disable Nginx
    if sudo systemctl is-active --quiet nginx 2>/dev/null; then
        log_info "Stopping Nginx service..."
        sudo systemctl stop nginx
        sudo systemctl disable nginx
        log_success "Nginx service stopped and disabled"
    fi
    
    # Remove systemd service files
    log_info "Removing systemd service files..."
    sudo rm -f /etc/systemd/system/ollama.service
    sudo rm -f /etc/systemd/system/stt.service
    sudo rm -f /etc/systemd/system/tts.service
    sudo systemctl daemon-reload
    log_success "Systemd service files removed"
}

# Remove Nginx configuration
cleanup_nginx() {
    log_step "Cleaning up Nginx Configuration"
    
    # Remove site configurations
    if [[ -d /etc/nginx/sites-enabled ]]; then
        log_info "Removing Nginx site configurations..."
        sudo rm -f /etc/nginx/sites-enabled/*
        log_success "Nginx site configurations removed"
    fi
    
    # Remove site-available configurations
    if [[ -d /etc/nginx/sites-available ]]; then
        log_info "Removing Nginx site-available configurations..."
        sudo rm -f /etc/nginx/sites-available/ai.conf
        sudo rm -f /etc/nginx/sites-available/api.conf
        sudo rm -f /etc/nginx/sites-available/local.conf
        log_success "Nginx site-available configurations removed"
    fi
    
    # Remove Let's Encrypt certificates if domains were configured
    if [[ -n "${DOMAIN_UI:-}" ]] || [[ -n "${DOMAIN_API:-}" ]]; then
        log_info "Removing Let's Encrypt certificates..."
        if [[ -n "${DOMAIN_UI:-}" ]]; then
            sudo certbot delete --cert-name "$DOMAIN_UI" --non-interactive 2>/dev/null || true
        fi
        if [[ -n "${DOMAIN_API:-}" ]]; then
            sudo certbot delete --cert-name "$DOMAIN_API" --non-interactive 2>/dev/null || true
        fi
        log_success "Let's Encrypt certificates removed"
    fi
    
    # Remove certbot cron job
    sudo rm -f /etc/cron.d/certbot
    log_success "Certbot cron job removed"
}

# Remove project directories
cleanup_directories() {
    log_step "Cleaning up Project Directories"
    
    local dirs=(
        "$HOME/ollama-webui"
        "$HOME/llama-router"
        "$HOME/voice"
        "$HOME/.local-ai-stack"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "Removing directory: $dir"
            rm -rf "$dir"
            log_success "Directory removed: $dir"
        fi
    done
}

# Remove Ollama installation
cleanup_ollama() {
    log_step "Cleaning up Ollama"
    
    # Remove Ollama binary
    if [[ -f /usr/local/bin/ollama ]]; then
        log_info "Removing Ollama binary..."
        sudo rm -f /usr/local/bin/ollama
        log_success "Ollama binary removed"
    fi
    
    # Remove Ollama models and data
    if [[ -d "$HOME/.ollama" ]]; then
        log_info "Removing Ollama models and data..."
        rm -rf "$HOME/.ollama"
        log_success "Ollama models and data removed"
    fi
}

# Remove environment variables
cleanup_environment() {
    log_step "Cleaning up Environment Variables"
    
    # Remove from .bashrc
    if [[ -f "$HOME/.bashrc" ]]; then
        log_info "Removing environment variables from .bashrc..."
        sed -i '/export PATH="\/usr\/local\/bin:\$PATH"/d' "$HOME/.bashrc"
        sed -i '/export OLLAMA_HOST=/d' "$HOME/.bashrc"
        log_success "Environment variables removed from .bashrc"
    fi
}

# Ask user about data preservation
confirm_cleanup() {
    log_step "Cleanup Confirmation"
    
    echo "This will remove all AI stack services and data."
    echo ""
    echo "Services to be removed:"
    echo "  - Ollama (models and data)"
    echo "  - Open WebUI"
    echo "  - Router service"
    echo "  - STT service"
    echo "  - TTS service"
    echo "  - Nginx reverse proxy"
    echo "  - All configuration files"
    echo ""
    
    read -p "Do you want to preserve any data? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Data preservation selected"
        PRESERVE_DATA=true
    else
        log_info "Full cleanup selected"
        PRESERVE_DATA=false
    fi
    
    echo ""
    read -p "Are you sure you want to proceed with cleanup? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
}

# Main cleanup function
main() {
    log_step "Local AI Stack Cleanup"
    
    # Confirm cleanup
    confirm_cleanup
    
    # Stop all services first
    log_info "Stopping all services..."
    
    # Cleanup Docker services
    cleanup_docker_services
    
    # Cleanup systemd services
    cleanup_systemd_services
    
    # Cleanup Nginx
    cleanup_nginx
    
    # Cleanup Ollama
    cleanup_ollama
    
    # Cleanup environment
    cleanup_environment
    
    # Remove project directories (unless preserving data)
    if [[ "$PRESERVE_DATA" == false ]]; then
        cleanup_directories
    else
        log_info "Skipping directory removal (data preservation enabled)"
    fi
    
    log_step "Cleanup Complete!"
    log_success "All AI stack services have been removed."
    
    if [[ "$PRESERVE_DATA" == true ]]; then
        log_info "Data directories have been preserved."
        log_info "To reinstall, run: ./install.sh"
    else
        log_info "All data has been removed."
        log_info "To reinstall from scratch, run: ./install.sh"
    fi
}

# Run main function
main
