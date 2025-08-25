#!/bin/bash

# Let's Encrypt Troubleshooting Script
# Helps diagnose and fix common certificate generation issues

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
    log_error "Configuration file not found: $CONFIG_FILE"
    log_info "Run the installer first: ./install.sh"
    exit 1
fi

check_domain_connectivity() {
    local domain="$1"
    log_info "Checking connectivity to $domain..."
    
    # Check if domain resolves
    log_info "Checking DNS resolution..."
    if nslookup "$domain" >/dev/null 2>&1; then
        local ip=$(nslookup "$domain" | grep -A1 "Name:" | tail -1 | awk '{print $2}')
        log_success "Domain resolves to: $ip"
        
        # Check if it resolves to this server
        local server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")
        if [[ "$ip" == "$server_ip" ]]; then
            log_success "Domain points to this server's IP"
        else
            log_warning "Domain points to $ip, but this server's IP is $server_ip"
            log_info "Update your DNS A record to point to this server"
        fi
    else
        log_error "Domain does not resolve"
        return 1
    fi
    
    # Check if port 80 is accessible
    log_info "Checking port 80 accessibility..."
    if timeout 5 bash -c "</dev/tcp/$domain/80" 2>/dev/null; then
        log_success "Port 80 is accessible"
    else
        log_error "Port 80 is not accessible"
        log_info "Let's Encrypt needs port 80 to be open for domain validation"
        return 1
    fi
    
    return 0
}

check_firewall() {
    log_info "Checking firewall configuration..."
    
    if command -v ufw &> /dev/null; then
        local ufw_status=$(sudo ufw status | grep "Status:")
        log_info "UFW Status: $ufw_status"
        
        if echo "$ufw_status" | grep -q "active"; then
            log_info "Checking if port 80 is allowed..."
            if sudo ufw status | grep -q "80"; then
                log_success "Port 80 is allowed in firewall"
            else
                log_warning "Port 80 may not be allowed in firewall"
                log_info "Run: sudo ufw allow 80"
            fi
        fi
    else
        log_warning "UFW not found - check your firewall manually"
    fi
}

check_certbot() {
    log_info "Checking Certbot installation..."
    
    if command -v certbot &> /dev/null; then
        log_success "Certbot is installed"
        log_info "Version: $(certbot --version)"
    else
        log_error "Certbot not found"
        log_info "Installing Certbot..."
        sudo apt-get update
        sudo apt-get install -y certbot
    fi
}

test_certificate_generation() {
    local domain="$1"
    log_info "Testing certificate generation for $domain..."
    
    # Try staging first
    log_info "Trying staging server (safe for testing)..."
    if sudo certbot certonly --standalone -d "$domain" --non-interactive --agree-tos --email admin@example.com --staging; then
        log_success "Staging certificate generated successfully"
        log_info "Removing staging certificate..."
        sudo certbot delete --cert-name "$domain" --non-interactive
        return 0
    else
        log_warning "Staging certificate generation failed"
        log_info "Check the error message above"
        return 1
    fi
}

main() {
    log_step "Let's Encrypt Troubleshooting"
    
    if [[ -z "${DOMAIN_UI:-}" ]]; then
        log_error "No domain configured"
        log_info "Run the installer with a domain: ./install.sh --domain-ui=yourdomain.com"
        exit 1
    fi
    
    log_info "Configured domains:"
    log_info "  WebUI: $DOMAIN_UI"
    log_info "  API: $DOMAIN_API"
    
    # Check prerequisites
    check_certbot
    check_firewall
    
    # Check domain connectivity
    log_info "Checking WebUI domain: $DOMAIN_UI"
    if check_domain_connectivity "$DOMAIN_UI"; then
        log_success "WebUI domain is accessible"
    else
        log_error "WebUI domain has connectivity issues"
    fi
    
    if [[ -n "${DOMAIN_API:-}" ]]; then
        log_info "Checking API domain: $DOMAIN_API"
        if check_domain_connectivity "$DOMAIN_API"; then
            log_success "API domain is accessible"
        else
            log_error "API domain has connectivity issues"
        fi
    fi
    
    # Test certificate generation
    log_info "Testing certificate generation..."
    if test_certificate_generation "$DOMAIN_UI"; then
        log_success "Certificate generation test passed"
        log_info "You can now run the installer again to generate production certificates"
    else
        log_error "Certificate generation test failed"
        log_info "Fix the issues above and try again"
    fi
    
    log_info "For more detailed logs, run:"
    log_info "  sudo journalctl -u certbot -f"
    log_info "  sudo certbot certonly --standalone -d $DOMAIN_UI --staging -v"
}

main
