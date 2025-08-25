#!/bin/bash

# Health Checks Script
# Verifies all services are running correctly

set -euo pipefail

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

CONFIG_FILE="$HOME/.local-ai-stack/config.env"
source "$CONFIG_FILE"

# Default values
OLLAMA_PORT=${OLLAMA_PORT:-11434}
WEBUI_PORT=${WEBUI_PORT:-8080}
ROUTER_PORT=${ROUTER_PORT:-5001}
STT_PORT=${STT_PORT:-5002}
TTS_PORT=${TTS_PORT:-5003}
DOMAIN_UI=${DOMAIN_UI:-""}
DOMAIN_API=${DOMAIN_API:-""}

# Test service health
test_service() {
    local service_name="$1"
    local url="$2"
    local expected_status="${3:-200}"
    
    log_info "Testing $service_name..."
    
    if curl -s -f -o /dev/null "$url"; then
        log_success "$service_name is healthy"
        return 0
    else
        log_error "$service_name health check failed"
        return 1
    fi
}

# Test Ollama
test_ollama() {
    log_step "Testing Ollama Service"
    
    # Test API endpoint
    if test_service "Ollama API" "http://127.0.0.1:$OLLAMA_PORT/api/tags"; then
        # Test model list
        local model_count
        model_count=$(curl -s "http://127.0.0.1:$OLLAMA_PORT/api/tags" | jq '.models | length' 2>/dev/null || echo "0")
        log_info "Ollama has $model_count models available"
    else
        return 1
    fi
}

# Test Router
test_router() {
    log_step "Testing Router Service"
    
    # Test health endpoint
    if test_service "Router Health" "http://127.0.0.1:$ROUTER_PORT/health"; then
        # Test models endpoint
        if test_service "Router Models" "http://127.0.0.1:$ROUTER_PORT/v1/models"; then
            log_success "Router is responding to OpenAI-compatible API"
        fi
    else
        return 1
    fi
}

# Test Open WebUI
test_webui() {
    log_step "Testing Open WebUI"
    
    if test_service "Open WebUI" "http://127.0.0.1:$WEBUI_PORT"; then
        log_success "Open WebUI is accessible"
    else
        return 1
    fi
}

# Test STT Service
test_stt() {
    log_step "Testing Speech-to-Text Service"
    
    if test_service "STT Health" "http://127.0.0.1:$STT_PORT/health"; then
        log_success "STT service is healthy"
        
        # Test transcription endpoint (would need actual audio file)
        log_info "STT transcription endpoint available at /transcribe"
    else
        return 1
    fi
}

# Test TTS Service
test_tts() {
    log_step "Testing Text-to-Speech Service"
    
    if test_service "TTS Health" "http://127.0.0.1:$TTS_PORT/health"; then
        log_success "TTS service is healthy"
        
        # Test speech endpoint
        if curl -s -f -o /dev/null "http://127.0.0.1:$TTS_PORT/speak?q=hello"; then
            log_success "TTS speech generation working"
        else
            log_warning "TTS speech generation test failed"
        fi
    else
        return 1
    fi
}

# Test Nginx
test_nginx() {
    log_step "Testing Nginx Reverse Proxy"
    
    # Test nginx process
    if sudo systemctl is-active --quiet nginx; then
        log_success "Nginx service is running"
    else
        log_error "Nginx service is not running"
        return 1
    fi
    
    # Test local proxy
    if test_service "Nginx Local" "http://127.0.0.1"; then
        log_success "Nginx local proxy is working"
    else
        return 1
    fi
    
    # Test domain proxies if configured
    if [[ -n "$DOMAIN_UI" ]]; then
        log_info "Testing WebUI domain: $DOMAIN_UI"
        if curl -s -f -o /dev/null "https://$DOMAIN_UI" 2>/dev/null; then
            log_success "WebUI domain proxy is working"
        else
            log_warning "WebUI domain proxy test failed (check DNS and SSL)"
        fi
    fi
    
    if [[ -n "$DOMAIN_API" ]]; then
        log_info "Testing API domain: $DOMAIN_API"
        if curl -s -f -o /dev/null "https://$DOMAIN_API/v1/models" 2>/dev/null; then
            log_success "API domain proxy is working"
        else
            log_warning "API domain proxy test failed (check DNS and SSL)"
        fi
    fi
}

# Test Docker services
test_docker_services() {
    log_step "Testing Docker Services"
    
    local services=("open-webui" "llama-router")
    local failed_services=()
    
    for service in "${services[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^$service$"; then
            log_success "Docker service $service is running"
        else
            log_error "Docker service $service is not running"
            failed_services+=("$service")
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log_warning "Failed services: ${failed_services[*]}"
        return 1
    fi
}

# Test systemd services
test_systemd_services() {
    log_step "Testing Systemd Services"
    
    local services=("ollama" "stt" "tts" "nginx")
    local failed_services=()
    
    for service in "${services[@]}"; do
        if sudo systemctl is-active --quiet "$service"; then
            log_success "Systemd service $service is running"
        else
            log_error "Systemd service $service is not running"
            failed_services+=("$service")
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log_warning "Failed services: ${failed_services[*]}"
        return 1
    fi
}

# Generate health report
generate_report() {
    log_step "Health Check Summary"
    
    local total_tests=6
    local passed_tests=0
    
    # Count passed tests
    if [[ $OLLAMA_HEALTH -eq 0 ]]; then ((passed_tests++)); fi
    if [[ $ROUTER_HEALTH -eq 0 ]]; then ((passed_tests++)); fi
    if [[ $WEBUI_HEALTH -eq 0 ]]; then ((passed_tests++)); fi
    if [[ $STT_HEALTH -eq 0 ]]; then ((passed_tests++)); fi
    if [[ $TTS_HEALTH -eq 0 ]]; then ((passed_tests++)); fi
    if [[ $NGINX_HEALTH -eq 0 ]]; then ((passed_tests++)); fi
    
    log_info "Health Check Results: $passed_tests/$total_tests services healthy"
    
    if [[ $passed_tests -eq $total_tests ]]; then
        log_success "All services are healthy! Your AI stack is ready to use."
        
        # Show access information
        log_step "Access Your AI Stack"
        
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
        
    else
        log_warning "Some services have issues. Check the logs above for details."
        log_info "Useful debugging commands:"
        log_info "  docker compose logs -f    # View Docker service logs"
        log_info "  sudo journalctl -u ollama -f  # View Ollama logs"
        log_info "  sudo journalctl -u stt -f     # View STT logs"
        log_info "  sudo journalctl -u tts -f     # View TTS logs"
        log_info "  sudo journalctl -u nginx -f   # View Nginx logs"
    fi
}

# Main function
main() {
    log_step "Running Health Checks"
    
    # Initialize health status variables
    OLLAMA_HEALTH=1
    ROUTER_HEALTH=1
    WEBUI_HEALTH=1
    STT_HEALTH=1
    TTS_HEALTH=1
    NGINX_HEALTH=1
    
    # Run all health checks
    test_ollama && OLLAMA_HEALTH=0
    test_router && ROUTER_HEALTH=0
    test_webui && WEBUI_HEALTH=0
    test_stt && STT_HEALTH=0
    test_tts && TTS_HEALTH=0
    test_nginx && NGINX_HEALTH=0
    
    # Test additional services
    test_docker_services
    test_systemd_services
    
    # Generate report
    generate_report
}

# Run main function
main
