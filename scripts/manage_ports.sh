#!/bin/bash

# Port Management Script
# Detects and cleans up port conflicts before installation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define logging functions locally
log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

log_warning() {
    echo -e "\033[0;33m[WARNING]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

log_step() {
    echo -e "\n\033[0;34m═══════════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[0;34m  $1\033[0m"
    echo -e "\033[0;34m═══════════════════════════════════════════════════════════════\033[0m\n"
}

# Load configuration
CONFIG_FILE="$HOME/.local-ai-stack/config.env"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    log_warning "Configuration file not found, using default ports"
    # Default ports
    OLLAMA_PORT=11434
    WEBUI_PORT=8080
    ROUTER_PORT=5001
    STT_PORT=5002
    TTS_PORT=5003
fi

# Function to check if a port is in use
check_port() {
    local port="$1"
    local service_name="$2"
    
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        log_warning "Port $port is in use by $service_name"
        return 0  # Port is in use
    else
        log_success "Port $port is available for $service_name"
        return 1  # Port is available
    fi
}

# Function to find what's using a port
find_port_usage() {
    local port="$1"
    
    # Try to find process using the port
    local pid=$(netstat -tuln 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | head -1)
    
    if [[ -n "$pid" ]]; then
        local process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
        local cmd_line=$(ps -p "$pid" -o args= 2>/dev/null || echo "unknown")
        log_info "Port $port is used by PID $pid ($process_name): $cmd_line"
        return "$pid"
    fi
    
    return 1
}

# Function to stop systemd service if it exists
stop_systemd_service() {
    local service_name="$1"
    local port="$2"
    
    if sudo systemctl list-units --full --all | grep -q "$service_name"; then
        log_info "Stopping systemd service: $service_name"
        sudo systemctl stop "$service_name" 2>/dev/null || true
        sudo systemctl disable "$service_name" 2>/dev/null || true
        log_success "Stopped systemd service: $service_name"
    fi
}

# Function to stop Docker containers using a port
stop_docker_on_port() {
    local port="$1"
    
    # Find containers using the port
    local containers=$(docker ps --format "{{.Names}}" --filter "publish=$port" 2>/dev/null || true)
    
    if [[ -n "$containers" ]]; then
        log_info "Found Docker containers using port $port: $containers"
        for container in $containers; do
            log_info "Stopping Docker container: $container"
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        done
        log_success "Stopped Docker containers using port $port"
    fi
}

# Function to kill Python processes on a port
kill_python_on_port() {
    local port="$1"
    
    # Find Python processes using the port
    local pids=$(netstat -tuln 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | grep -v "^$" || true)
    
    if [[ -n "$pids" ]]; then
        for pid in $pids; do
            local process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            if [[ "$process_name" == "python"* ]] || [[ "$process_name" == "uvicorn"* ]] || [[ "$process_name" == "gunicorn"* ]]; then
                log_info "Killing Python process $pid ($process_name) on port $port"
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
        log_success "Killed Python processes on port $port"
    fi
}

# Function to clean up specific service ports
cleanup_service_port() {
    local port="$1"
    local service_name="$2"
    
    log_info "Checking port $port for $service_name..."
    
    if check_port "$port" "$service_name"; then
        log_warning "Port $port is in use, attempting to clean up..."
        
        # Stop Docker containers first
        stop_docker_on_port "$port"
        
        # Kill Python processes
        kill_python_on_port "$port"
        
        # Wait a moment for cleanup
        sleep 2
        
        # Check if port is now available
        if check_port "$port" "$service_name"; then
            log_error "Port $port is still in use after cleanup"
            return 1
        else
            log_success "Port $port is now available for $service_name"
            return 0
        fi
    fi
    
    return 0
}

# Function to clean up all service ports
cleanup_all_ports() {
    log_step "Port Conflict Detection and Cleanup"
    
    # Check if we should accept existing services
    if [[ "${ACCEPT_EXISTING:-false}" == "true" ]]; then
        log_info "Accepting existing services - checking port availability only"
        local ports_to_check=(
            "$OLLAMA_PORT:Ollama"
            "$WEBUI_PORT:Open WebUI"
            "$ROUTER_PORT:Router"
            "$STT_PORT:STT Service"
            "$TTS_PORT:TTS Service"
        )
        
        for port_service in "${ports_to_check[@]}"; do
            local port="${port_service%:*}"
            local service="${port_service#*:}"
            
            if check_port "$port" "$service"; then
                log_info "Port $port is in use by $service - this is expected with --accept-existing"
            else
                log_success "Port $port is available for $service"
            fi
        done
        
        log_success "Port check completed with --accept-existing mode"
        return 0
    fi
    
    local ports_to_check=(
        "$OLLAMA_PORT:Ollama"
        "$WEBUI_PORT:Open WebUI"
        "$ROUTER_PORT:Router"
        "$STT_PORT:STT Service"
        "$TTS_PORT:TTS Service"
    )
    
    local cleanup_needed=false
    
    # First pass: check all ports
    for port_service in "${ports_to_check[@]}"; do
        local port="${port_service%:*}"
        local service="${port_service#*:}"
        
        if check_port "$port" "$service"; then
            cleanup_needed=true
        fi
    done
    
    if [[ "$cleanup_needed" == "false" ]]; then
        log_success "All ports are available - no cleanup needed"
        return 0
    fi
    
    log_info "Port conflicts detected, starting cleanup process..."
    
    # Second pass: clean up each port
    for port_service in "${ports_to_check[@]}"; do
        local port="${port_service%:*}"
        local service="${port_service#*:}"
        
        cleanup_service_port "$port" "$service"
    done
    
    # Final check
    log_info "Final port availability check..."
    local all_clean=true
    
    for port_service in "${ports_to_check[@]}"; do
        local port="${port_service%:*}"
        local service="${port_service#*:}"
        
        if check_port "$port" "$service"; then
            all_clean=false
        fi
    done
    
    if [[ "$all_clean" == "true" ]]; then
        log_success "All ports are now available!"
        return 0
    else
        log_warning "Some ports are still in use after cleanup"
        log_info "You may need to manually stop services or choose different ports"
        return 0  # Continue anyway, user can handle manually
    fi
}

# Function to show current port usage
show_port_usage() {
    log_step "Current Port Usage"
    
    local ports_to_check=(
        "$OLLAMA_PORT:Ollama"
        "$WEBUI_PORT:Open WebUI"
        "$ROUTER_PORT:Router"
        "$STT_PORT:STT Service"
        "$TTS_PORT:TTS Service"
    )
    
    for port_service in "${ports_to_check[@]}"; do
        local port="${port_service%:*}"
        local service="${port_service#*:}"
        
        if check_port "$port" "$service"; then
            find_port_usage "$port"
        fi
    done
}

# Function to force kill everything on a port
force_cleanup_port() {
    local port="$1"
    local service_name="$2"
    
    log_warning "Force cleaning port $port for $service_name..."
    
    # Kill all processes on the port
    local pids=$(netstat -tuln 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | grep -v "^$" || true)
    
    if [[ -n "$pids" ]]; then
        for pid in $pids; do
            log_info "Force killing process $pid on port $port"
            kill -9 "$pid" 2>/dev/null || true
        done
    fi
    
    # Stop Docker containers
    stop_docker_on_port "$port"
    
    # Wait and check
    sleep 3
    if check_port "$port" "$service_name"; then
        log_error "Port $port is still in use after force cleanup"
        return 1
    else
        log_success "Port $port is now available after force cleanup"
        return 0
    fi
}

# Main function
main() {
    case "${1:-cleanup}" in
        "check")
            show_port_usage
            ;;
        "cleanup")
            cleanup_all_ports
            ;;
        "force")
            log_warning "Force cleanup mode - this will kill all processes on service ports"
            read -p "Are you sure? This may stop other services (y/N): " -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                force_cleanup_port "$OLLAMA_PORT" "Ollama"
                force_cleanup_port "$WEBUI_PORT" "Open WebUI"
                force_cleanup_port "$ROUTER_PORT" "Router"
                force_cleanup_port "$STT_PORT" "STT Service"
                force_cleanup_port "$TTS_PORT" "TTS Service"
            else
                log_info "Force cleanup cancelled"
            fi
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  check     - Show current port usage"
            echo "  cleanup   - Clean up port conflicts (default)"
            echo "  force     - Force kill all processes on service ports"
            echo "  help      - Show this help message"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
