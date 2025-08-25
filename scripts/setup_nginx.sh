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
    if [[ -n "$DOMAIN_UI" ]] || [[ -n "$DOMAIN_API" ]]; then
        setup_nginx_with_domains
    else
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
    
    # Setup TLS certificates
    setup_tls_certificates
}

setup_nginx_local_only() {
    log_info "Setting up Nginx for local access only..."
    
    # Create local WebUI configuration
    sudo tee /etc/nginx/sites-available/local.conf > /dev/null << EOF
server {
    listen 80;
    server_name _;
    
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
}
EOF
    
    sudo ln -sf /etc/nginx/sites-available/local.conf /etc/nginx/sites-enabled/
    log_info "Local-only configuration created"
}

setup_tls_certificates() {
    log_info "Setting up TLS certificates with Let's Encrypt..."
    
    # Stop nginx temporarily for certificate generation
    sudo systemctl stop nginx
    
    # Generate certificates
    if [[ -n "$DOMAIN_UI" ]]; then
        log_info "Generating certificate for $DOMAIN_UI..."
        sudo certbot certonly --standalone -d "$DOMAIN_UI" --non-interactive --agree-tos --email admin@example.com
    fi
    
    if [[ -n "$DOMAIN_API" ]]; then
        log_info "Generating certificate for $DOMAIN_API..."
        sudo certbot certonly --standalone -d "$DOMAIN_API" --non-interactive --agree-tos --email admin@example.com
    fi
    
    # Setup automatic renewal
    sudo tee /etc/cron.d/certbot > /dev/null << EOF
0 12 * * * /usr/bin/certbot renew --quiet
EOF
    
    # Start nginx again
    sudo systemctl start nginx
    
    log_success "TLS certificates configured and automatic renewal scheduled"
}

main() {
    setup_nginx
}

main
