# Local AI Stack Management Makefile
# Provides easy commands for managing all services

.PHONY: help up down logs status restart clean install uninstall

# Load configuration
CONFIG_FILE := $(HOME)/.local-ai-stack/config.env
ifneq (,$(wildcard $(CONFIG_FILE)))
    include $(CONFIG_FILE)
endif

# Default values
WEBUI_PORT ?= 8080
ROUTER_PORT ?= 1338
STT_PORT ?= 5002
TTS_PORT ?= 5003

help: ## Show this help message
	@echo "Local AI Stack Management Commands:"
	@echo ""
	@echo "Service Management:"
	@echo "  make up              # Start all services"
	@echo "  make down            # Stop all services"
	@echo "  make restart         # Restart all services"
	@echo "  make status          # Show status of all services"
	@echo ""
	@echo "Individual Services:"
	@echo "  make up-ollama       # Start Ollama service"
	@echo "  make up-webui        # Start Open WebUI"
	@echo "  make up-router       # Start Router service"
	@echo "  make up-stt          # Start STT service"
	@echo "  make up-tts          # Start TTS service"
	@echo "  make up-nginx        # Start Nginx proxy"
	@echo ""
	@echo "Logs and Monitoring:"
	@echo "  make logs            # View all service logs"
	@echo "  make logs-webui      # View WebUI logs"
	@echo "  make logs-router     # View Router logs"
	@echo "  make logs-stt        # View STT logs"
	@echo "  make logs-tts        # View TTS logs"
	@echo ""
	@echo "Maintenance:"
	@echo "  make health          # Run health checks"
	@echo "  make clean           # Clean up containers and volumes"
	@echo "  make install         # Run full installation"
	@echo "  make uninstall       # Remove all services and data"

# Start all services
up: ## Start all services
	@echo "Starting all AI stack services..."
	@$(MAKE) up-ollama
	@$(MAKE) up-webui
	@$(MAKE) up-router
	@$(MAKE) up-stt
	@$(MAKE) up-tts
	@$(MAKE) up-nginx
	@echo "All services started!"

# Stop all services
down: ## Stop all services
	@echo "Stopping all AI stack services..."
	@$(MAKE) down-webui
	@$(MAKE) down-router
	@$(MAKE) down-stt
	@$(MAKE) down-tts
	@$(MAKE) down-nginx
	@$(MAKE) down-ollama
	@echo "All services stopped!"

# Restart all services
restart: ## Restart all services
	@echo "Restarting all AI stack services..."
	@$(MAKE) down
	@$(MAKE) up
	@echo "All services restarted!"

# Show status of all services
status: ## Show status of all services
	@echo "=== AI Stack Service Status ==="
	@echo ""
	@echo "Systemd Services:"
	@sudo systemctl status ollama --no-pager -l || true
	@sudo systemctl status stt --no-pager -l || true
	@sudo systemctl status tts --no-pager -l || true
	@sudo systemctl status nginx --no-pager -l || true
	@echo ""
	@echo "Docker Services:"
	@docker ps --filter "name=open-webui" --filter "name=llama-router" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true

# Start individual services
up-ollama: ## Start Ollama service
	@echo "Starting Ollama service..."
	@sudo systemctl start ollama || true
	@sudo systemctl enable ollama || true

up-webui: ## Start Open WebUI
	@echo "Starting Open WebUI..."
	@cd $(HOME)/ollama-webui && docker compose up -d || true

up-router: ## Start Router service
	@echo "Starting Router service..."
	@cd $(HOME)/llama-router && docker compose up -d || true

up-stt: ## Start STT service
	@echo "Starting STT service..."
	@sudo systemctl start stt || true
	@sudo systemctl enable stt || true

up-tts: ## Start TTS service
	@echo "Starting TTS service..."
	@sudo systemctl start tts || true
	@sudo systemctl enable tts || true

up-nginx: ## Start Nginx proxy
	@echo "Starting Nginx proxy..."
	@sudo systemctl start nginx || true
	@sudo systemctl enable nginx || true

# Stop individual services
down-ollama: ## Stop Ollama service
	@echo "Stopping Ollama service..."
	@sudo systemctl stop ollama || true

down-webui: ## Stop Open WebUI
	@echo "Stopping Open WebUI..."
	@cd $(HOME)/ollama-webui && docker compose down || true

down-router: ## Stop Router service
	@echo "Stopping Router service..."
	@cd $(HOME)/llama-router && docker compose down || true

down-stt: ## Stop STT service
	@echo "Stopping STT service..."
	@sudo systemctl stop stt || true

down-tts: ## Stop TTS service
	@echo "Stopping TTS service..."
	@sudo systemctl stop tts || true

down-nginx: ## Stop Nginx proxy
	@echo "Stopping Nginx proxy..."
	@sudo systemctl stop nginx || true

# View logs
logs: ## View all service logs
	@echo "=== AI Stack Service Logs ==="
	@echo ""
	@echo "Docker Services:"
	@cd $(HOME)/ollama-webui && docker compose logs --tail=20 || true
	@cd $(HOME)/llama-router && docker compose logs --tail=20 || true
	@echo ""
	@echo "Systemd Services:"
	@sudo journalctl -u ollama --no-pager -n 20 || true
	@sudo journalctl -u stt --no-pager -n 20 || true
	@sudo journalctl -u tts --no-pager -n 20 || true
	@sudo journalctl -u nginx --no-pager -n 20 || true

logs-webui: ## View WebUI logs
	@echo "=== Open WebUI Logs ==="
	@cd $(HOME)/ollama-webui && docker compose logs -f

logs-router: ## View Router logs
	@echo "=== Router Service Logs ==="
	@cd $(HOME)/llama-router && docker compose logs -f

logs-stt: ## View STT logs
	@echo "=== STT Service Logs ==="
	@sudo journalctl -u stt -f

logs-tts: ## View TTS logs
	@echo "=== TTS Service Logs ==="
	@sudo journalctl -u tts -f

# Health checks
health: ## Run health checks
	@echo "Running health checks..."
	@./scripts/health_checks.sh

# Clean up
clean: ## Clean up containers and volumes
	@echo "Cleaning up containers and volumes..."
	@cd $(HOME)/ollama-webui && docker compose down -v || true
	@cd $(HOME)/llama-router && docker compose down -v || true
	@docker system prune -f || true
	@echo "Cleanup completed!"

# Installation
install: ## Run full installation
	@echo "Running full AI stack installation..."
	@./install.sh

uninstall: ## Remove all services and data
	@echo "Uninstalling AI stack..."
	@./cleanup.sh

# Quick access URLs
urls: ## Show service URLs
	@echo "=== AI Stack Service URLs ==="
	@echo ""
	@echo "Local Access:"
	@echo "  WebUI:     http://127.0.0.1:$(WEBUI_PORT)"
	@echo "  Router:    http://127.0.0.1:$(ROUTER_PORT)/v1"
	@echo "  STT:       http://127.0.0.1:$(STT_PORT)"
	@echo "  TTS:       http://127.0.0.1:$(TTS_PORT)"
	@echo "  Nginx:     http://127.0.0.1"
	@echo ""
ifdef DOMAIN_UI
	@echo "Domain Access:"
	@echo "  WebUI:     https://$(DOMAIN_UI)"
endif
ifdef DOMAIN_API
	@echo "  API:       https://$(DOMAIN_API)/v1"
endif
	@echo ""
	@echo "Health Checks:"
	@echo "  Ollama:    http://127.0.0.1:11434/api/tags"
	@echo "  Router:    http://127.0.0.1:$(ROUTER_PORT)/health"
	@echo "  STT:       http://127.0.0.1:$(STT_PORT)/health"
	@echo "  TTS:       http://127.0.0.1:$(TTS_PORT)/health"
