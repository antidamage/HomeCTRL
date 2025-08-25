#!/bin/bash

# Nginx Setup Script
# Sets up reverse proxy with optional TLS support

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

DOMAIN_UI=${DOMAIN_UI:-""}
DOMAIN_API=${DOMAIN_API:-""}
WEBUI_PORT=${WEBUI_PORT:-8080}
ROUTER_PORT=${ROUTER_PORT:-1338}

setup_nginx() {
    log_step "Setting up Nginx Reverse Proxy"
    
    # Create nginx configuration directory
    sudo mkdir -p /etc/nginx/sites-available
    sudo mkdir -p /etc/nginx/sites-enabled
    
    # Create main nginx configuration
    if [[ -n "$DOMAIN_UI" ]] && [[ -n "$DOMAIN_API" ]]; then
        log_info "Setting up Nginx with domain support and TLS..."
        setup_nginx_with_domains
    else
        log_info "Setting up Nginx for local access only..."
        setup_nginx_local_only
    fi
    
    # Test configuration
    if sudo nginx -t; then
        log_success "Nginx configuration is valid"
    else
        log_error "Nginx configuration is invalid"
        exit 1
    fi
    
    # Restart nginx
    sudo systemctl restart nginx
    sudo systemctl enable nginx
    
    log_success "Nginx reverse proxy configured and started"
}

setup_nginx_with_domains() {
    log_info "Setting up Nginx with domain support and TLS..."
    
    # Create WebUI site configuration
    if [[ -n "$DOMAIN_UI" ]]; then
        sudo tee /etc/nginx/sites-available/ai.conf > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN_UI;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN_UI;
    
    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_UI/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_UI/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    # Proxy to WebUI
    location / {
        proxy_pass http://127.0.0.1:$WEBUI_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering off;
        client_max_body_size 50M;
    }
}
EOF
        sudo ln -sf /etc/nginx/sites-available/ai.conf /etc/nginx/sites-enabled/
        log_info "WebUI site configured for $DOMAIN_UI"
    fi
    
    # Create API site configuration
    if [[ -n "$DOMAIN_API" ]]; then
        sudo tee /etc/nginx/sites-available/api.conf > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN_API;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN_API;
    
    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_API/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_API/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    # Proxy to Router API
    location / {
        proxy_pass http://127.0.0.1:$ROUTER_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering off;
        client_max_body_size 50M;
    }
}
EOF
        sudo ln -sf /etc/nginx/sites-available/api.conf /etc/nginx/sites-enabled/
        log_info "API site configured for $DOMAIN_API"
    fi
    
    # Setup TLS certificates only if domains are configured
    if [[ -n "$DOMAIN_UI" ]] && [[ -n "$DOMAIN_API" ]]; then
        setup_tls_certificates
    else
        log_info "Skipping TLS setup (no domains configured)"
    fi
}

setup_nginx_local_only() {
    log_info "Setting up Nginx for local access only..."
    
    # Create local configuration with all services
    sudo tee /etc/nginx/sites-available/local.conf > /dev/null << EOF
server {
    listen 80;
    server_name localhost;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    # Proxy to WebUI (main interface)
    location / {
        proxy_pass http://127.0.0.1:$WEBUI_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering off;
        client_max_body_size 50M;
    }
    
    # Proxy to Router API
    location /api/ {
        proxy_pass http://127.0.0.1:$ROUTER_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering off;
        client_max_body_size 50M;
    }
    
    # Proxy to STT service
    location /stt/ {
        proxy_pass http://127.0.0.1:$STT_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering off;
        client_max_body_size 50M;
    }
    
    # Proxy to TTS service
    location /tts/ {
        proxy_pass http://127.0.0.1:$TTS_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering off;
        client_max_body_size 50M;
    }
}
EOF
    
    sudo ln -sf /etc/nginx/sites-available/local.conf /etc/nginx/sites-enabled/
    log_info "Local-only configuration created with all services accessible via localhost"
}

check_domain_connectivity() {
    local domain="$1"
    log_info "Checking connectivity to $domain..."
    
    # Check if domain resolves
    if ! nslookup "$domain" >/dev/null 2>&1; then
        log_warning "Domain $domain does not resolve to an IP address"
        log_info "Make sure your domain points to this server's IP address"
        return 1
    fi
    
    # Check if port 80 is accessible (needed for Let's Encrypt validation)
    if ! timeout 5 bash -c "</dev/tcp/$domain/80" 2>/dev/null; then
        log_warning "Port 80 is not accessible on $domain"
        log_info "Let's Encrypt needs port 80 to be open for domain validation"
        return 1
    fi
    
    log_success "Domain $domain is accessible"
    return 0
}

setup_tls_certificates() {
    log_info "Setting up TLS certificates with Let's Encrypt..."
    
    # Check if certbot is available
    if ! command -v certbot &> /dev/null; then
        log_error "Certbot not found. Installing..."
        sudo apt-get update
        sudo apt-get install -y certbot
    fi
    
    # Stop nginx temporarily for certificate generation
    sudo systemctl stop nginx
    
    # Generate certificates with better error handling
    local success_count=0
    local total_domains=0
    
    if [[ -n "$DOMAIN_UI" ]]; then
        ((total_domains++))
        if check_domain_connectivity "$DOMAIN_UI"; then
            log_info "Generating certificate for $DOMAIN_UI..."
            if sudo certbot certonly --standalone -d "$DOMAIN_UI" --non-interactive --agree-tos --email admin@example.com --staging; then
                log_success "Certificate generated for $DOMAIN_UI"
                ((success_count++))
            else
                log_warning "Failed to generate certificate for $DOMAIN_UI (staging)"
                log_info "Trying production server..."
                if sudo certbot certonly --standalone -d "$DOMAIN_UI" --non-interactive --agree-tos --email admin@example.com; then
                    log_success "Certificate generated for $DOMAIN_UI (production)"
                    ((success_count++))
                else
                    log_error "Failed to generate certificate for $DOMAIN_UI"
                    log_info "Check the logs: sudo journalctl -u certbot -f"
                fi
            fi
        else
            log_error "Skipping certificate generation for $DOMAIN_UI due to connectivity issues"
        fi
    fi
    
    if [[ -n "$DOMAIN_API" ]]; then
        ((total_domains++))
        if check_domain_connectivity "$DOMAIN_API"; then
            log_info "Generating certificate for $DOMAIN_API..."
            if sudo certbot certonly --standalone -d "$DOMAIN_API" --non-interactive --agree-tos --email admin@example.com --staging; then
                log_success "Certificate generated for $DOMAIN_API"
                ((success_count++))
            else
                log_warning "Failed to generate certificate for $DOMAIN_API (staging)"
                log_info "Trying production server..."
                if sudo certbot certonly --standalone -d "$DOMAIN_API" --non-interactive --agree-tos --email admin@example.com; then
                    log_success "Certificate generated for $DOMAIN_API (production)"
                    ((success_count++))
                else
                    log_error "Failed to generate certificate for $DOMAIN_API"
                    log_info "Check the logs: sudo journalctl -u certbot -f"
                fi
            fi
        else
            log_error "Skipping certificate generation for $DOMAIN_API due to connectivity issues"
        fi
    fi
    
    # Setup automatic renewal only if we have certificates
    if [[ $success_count -gt 0 ]]; then
        sudo tee /etc/cron.d/certbot > /dev/null << EOF
0 12 * * * /usr/bin/certbot renew --quiet
EOF
        log_success "Automatic renewal scheduled for $success_count/$total_domains domains"
    fi
    
    # Start nginx again
    sudo systemctl start nginx
    
    if [[ $success_count -eq $total_domains ]]; then
        log_success "TLS certificates configured successfully for all domains"
    elif [[ $success_count -gt 0 ]]; then
        log_warning "TLS certificates configured for $success_count/$total_domains domains"
        log_info "Some domains may not have HTTPS - check the logs above"
    else
        log_error "Failed to generate any TLS certificates"
        log_info "Check your domain configuration and network connectivity"
        log_info "You can run: sudo certbot certonly --standalone -d yourdomain.com --staging -v"
    fi
}

main() {
    setup_nginx
}

main
