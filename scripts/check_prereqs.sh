#!/bin/bash

# Prerequisites Check and Installation Script
# Ensures all required packages and tools are available

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

# Package lists
PACKAGES=(
    "curl"
    "wget"
    "git"
    "build-essential"
    "python3"
    "python3-pip"
    "python3-venv"
    "python3-dev"
    "ffmpeg"
    "ca-certificates"
    "nginx"
    "certbot"
    "python3-certbot-nginx"
    "ufw"
    "net-tools"
    "software-properties-common"
    "apt-transport-https"
    "ca-certificates"
    "gnupg"
    "lsb-release"
)

# Check if running as root for package installation
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log_error "This script requires sudo access to install packages"
        log_info "Please run: sudo -v"
        exit 1
    fi
}

# Update package lists
update_packages() {
    log_info "Updating package lists..."
    sudo apt update
    log_success "Package lists updated"
}

# Install system packages
install_packages() {
    log_info "Installing system packages..."
    
    local missing_packages=()
    
    for package in "${PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            missing_packages+=("$package")
        fi
    done
    
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        log_success "All required packages are already installed"
        return 0
    fi
    
    log_info "Installing missing packages: ${missing_packages[*]}"
    sudo apt install -y "${missing_packages[@]}"
    log_success "System packages installed successfully"
}

# Install Docker
install_docker() {
    log_info "Checking Docker installation..."
    
    if command -v docker &> /dev/null; then
        log_success "Docker is already installed"
        return 0
    fi
    
    log_info "Installing Docker..."
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package lists
    sudo apt update
    
    # Install Docker
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add user to docker group (optional, for convenience)
    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER"
        log_warning "Added user to docker group. You may need to log out and back in for this to take effect."
    fi
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Verify Docker Compose plugin
    if ! docker compose version >/dev/null 2>&1; then
        log_info "Installing Docker Compose plugin..."
        sudo apt-get update
        sudo apt-get install -y docker-compose-plugin
    fi
    
    # Add user to docker group if not already added
    if ! groups | grep -q docker; then
        log_info "Adding user to docker group..."
        sudo usermod -aG docker "$USER"
        log_warning "You need to log out and back in for docker group changes to take effect"
        log_warning "Or run: newgrp docker"
    fi
    
    log_success "Docker installed and started successfully"
}

# Install NVIDIA Container Toolkit
install_nvidia_container_toolkit() {
    log_info "Checking NVIDIA Container Toolkit..."
    
    if command -v nvidia-container-runtime &> /dev/null; then
        log_success "NVIDIA Container Toolkit is already installed"
        return 0
    fi
    
    # Check if NVIDIA GPU is present
    if ! command -v nvidia-smi &> /dev/null; then
        log_warning "NVIDIA GPU not detected or drivers not installed"
        log_info "Skipping NVIDIA Container Toolkit installation"
        return 0
    fi
    
    log_info "Installing NVIDIA Container Toolkit..."
    
    # Add NVIDIA repository
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-docker-keyring.gpg
    
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-docker-keyring.gpg] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
    
    # Update and install
    sudo apt update
    sudo apt install -y nvidia-container-toolkit
    
    # Restart Docker
    sudo systemctl restart docker
    
    log_success "NVIDIA Container Toolkit installed successfully"
}

# Install Python packages
install_python_packages() {
    log_info "Installing Python packages..."
    
    # Upgrade pip
    python3 -m pip install --upgrade pip
    
    # Install required Python packages
    # Note: docker-compose is now handled by the Docker Compose plugin
    
    log_success "Python packages installed successfully"
}

# Configure firewall
configure_firewall() {
    log_info "Configuring firewall..."
    
    # Enable UFW if not already enabled
    if ! sudo ufw status | grep -q "Status: active"; then
        sudo ufw --force enable
    fi
    
    # Allow SSH (important!)
    sudo ufw allow ssh
    
    # Allow WebUI port on LAN
    if [[ -n "${WEBUI_PORT:-}" ]]; then
        sudo ufw allow from 192.168.0.0/16 to any port "$WEBUI_PORT"
        log_info "Allowed WebUI port $WEBUI_PORT from LAN"
    fi
    
    # Allow HTTP/HTTPS for nginx
    sudo ufw allow 80
    sudo ufw allow 443
    
    log_success "Firewall configured successfully"
}

# Check and clean up port conflicts
check_port_conflicts() {
    log_info "Checking for port conflicts..."
    
    # Load configuration if available
    if [[ -f "$HOME/.local-ai-stack/config.env" ]]; then
        source "$HOME/.local-ai-stack/config.env"
    fi
    
    # Default ports if not configured
    local ollama_port=${OLLAMA_PORT:-11434}
    local webui_port=${WEBUI_PORT:-8080}
    local router_port=${ROUTER_PORT:-5001}
    local stt_port=${STT_PORT:-5002}
    local tts_port=${TTS_PORT:-5003}
    
    local ports_to_check=(
        "$ollama_port:Ollama"
        "$webui_port:Open WebUI"
        "$router_port:Router"
        "$stt_port:STT Service"
        "$tts_port:TTS Service"
    )
    
    local cleanup_needed=false
    
    # Check each port
    for port_service in "${ports_to_check[@]}"; do
        local port="${port_service%:*}"
        local service="${port_service#*:}"
        
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_warning "Port $port is in use by $service"
            cleanup_needed=true
        fi
    done
    
    if [[ "$cleanup_needed" == "false" ]]; then
        log_success "All required ports are available"
        return 0
    fi
    
    log_info "Port conflicts detected. Attempting to clean up existing services..."
    
    # Try to stop existing services
    for port_service in "${ports_to_check[@]}"; do
        local port="${port_service%:*}"
        local service="${port_service#*:}"
        
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_info "Cleaning up port $port for $service..."
            
            # Stop Docker containers
            local containers=$(docker ps --format "{{.Names}}" --filter "publish=$port" 2>/dev/null || true)
            if [[ -n "$containers" ]]; then
                log_info "Stopping Docker containers on port $port: $containers"
                for container in $containers; do
                    docker stop "$container" 2>/dev/null || true
                    docker rm "$container" 2>/dev/null || true
                done
            fi
            
            # Kill Python processes
            local pids=$(netstat -tuln 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | grep -v "^$" || true)
            if [[ -n "$pids" ]]; then
                for pid in $pids; do
                    local process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
                    if [[ "$process_name" == "python"* ]] || [[ "$process_name" == "uvicorn"* ]] || [[ "$process_name" == "gunicorn"* ]]; then
                        log_info "Killing Python process $pid on port $port"
                        kill -9 "$pid" 2>/dev/null || true
                    fi
                done
            fi
            
            # Stop systemd services if they exist
            case "$service" in
                "Ollama")
                    if sudo systemctl list-units --full --all | grep -q "ollama"; then
                        log_info "Stopping Ollama systemd service"
                        sudo systemctl stop ollama 2>/dev/null || true
                        sudo systemctl disable ollama 2>/dev/null || true
                    fi
                    ;;
                "STT Service")
                    if sudo systemctl list-units --full --all | grep -q "stt"; then
                        log_info "Stopping STT systemd service"
                        sudo systemctl stop stt 2>/dev/null || true
                        sudo systemctl disable stt 2>/dev/null || true
                    fi
                    ;;
                "TTS Service")
                    if sudo systemctl list-units --full --all | grep -q "tts"; then
                        log_info "Stopping TTS systemd service"
                        sudo systemctl stop tts 2>/dev/null || true
                        sudo systemctl disable tts 2>/dev/null || true
                    fi
                    ;;
            esac
        fi
    done
    
    # Wait for cleanup
    sleep 3
    
    # Final check
    log_info "Final port availability check..."
    local all_clean=true
    
    for port_service in "${ports_to_check[@]}"; do
        local port="${port_service%:*}"
        local service="${port_service#*:}"
        
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_warning "Port $port is still in use by $service"
            all_clean=false
        else
            log_success "Port $port is now available for $service"
        fi
    done
    
    if [[ "$all_clean" == "true" ]]; then
        log_success "All ports are now available!"
        return 0
    else
        log_warning "Some ports are still in use after cleanup"
        log_info "You may need to manually stop services or choose different ports"
        log_info "Run './scripts/manage_ports.sh check' to see what's using the ports"
        return 0  # Continue anyway, user can handle manually
    fi
}

# Create project directories
create_directories() {
    log_info "Creating project directories..."
    
    local dirs=(
        "$HOME/ollama-webui"
        "$HOME/llama-router"
        "$HOME/voice/stt"
        "$HOME/voice/tts"
        "$HOME/.local-ai-stack"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "Created directory: $dir"
        fi
    done
    
    log_success "Project directories created"
}

# Check system requirements
check_system_requirements() {
    log_info "Checking system requirements..."
    
    # Check RAM
    local total_ram
    total_ram=$(free -m | awk 'NR==2{printf "%.0f", $2/1024}')
    
    if [[ $total_ram -lt 16 ]]; then
        log_warning "System has ${total_ram}GB RAM. Recommended: 16GB+"
        read -p "Continue anyway? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "RAM: ${total_ram}GB (✓)"
    fi
    
    # Check disk space
    local available_space
    available_space=$(df -BG "$HOME" | awk 'NR==2{print $4}' | sed 's/G//')
    
    if [[ $available_space -lt 50 ]]; then
        log_warning "Available disk space: ${available_space}GB. Recommended: 50GB+"
        read -p "Continue anyway? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "Disk space: ${available_space}GB (✓)"
    fi
    
    # Check if running on Ubuntu 22.04
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" == "ubuntu" ]] && [[ "$VERSION_ID" == "22.04" ]]; then
            log_success "OS: Ubuntu 22.04 LTS (✓)"
        else
            log_error "OS: $ID $VERSION_ID"
            log_error "This installer is designed exclusively for Ubuntu 22.04 LTS"
            log_error ""
            log_error "To use this installer, you must:"
            log_error "1. Install Ubuntu Server 22.04 LTS, OR"
            log_error "2. Install WSL2 with Ubuntu 22.04 LTS on Windows"
            log_error ""
            log_error "For WSL2 installation: https://docs.microsoft.com/en-us/windows/wsl/install"
            exit 1
        fi
    fi
}

# Main function
main() {
    log_step "Prerequisites Check and Installation"
    
    # Check system requirements
    check_system_requirements
    
    # Check sudo access
    check_sudo
    
    # Update package lists
    update_packages
    
    # Install system packages
    install_packages
    
    # Install Docker
    install_docker
    
    # Install NVIDIA Container Toolkit
    install_nvidia_container_toolkit
    
    # Install Python packages
    install_python_packages
    
    # Configure firewall
    configure_firewall
    
    # Check and clean up port conflicts
    check_port_conflicts
    
    # Create project directories
    create_directories
    
    log_success "All prerequisites are installed and configured!"
    log_info "You can now proceed with the AI stack installation."
}

# Run main function
main
