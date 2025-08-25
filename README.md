# Local AI Stack Installer

A comprehensive, guided installer for setting up a full local AI rig on Ubuntu Server 22.04 LTS with NVIDIA GPU support.

**⚠️ IMPORTANT**: This installer is designed **EXCLUSIVELY** for Ubuntu 22.04 LTS. It will not work on other Linux distributions or operating systems. For Windows users, WSL2 with Ubuntu 22.04 LTS is supported.

## Features

- **Ollama**: Local model hosting with llama3:8b, qwen2.5:14b-instruct, and deepseek-coder:6.7b-instruct
- **Open WebUI**: Modern web interface for chatting with models
- **Router**: Intelligent model routing with auto-escalation, web search, and OCR capabilities
- **STT/TTS**: Speech-to-text and text-to-speech services
- **Nginx**: Reverse proxy with optional TLS support
- **Vision Models**: Optional support for qwen2.5-vl:7b-instruct or llava:13b

## Quick Start

### For Ubuntu Server 22.04 LTS Users
```bash
# Clone and run
git clone <your-repo>
cd HomeAI
chmod +x install.sh scripts/*.sh cleanup.sh
./install.sh
```

### For Windows Users (WSL2)
```bash
# Install WSL2 with Ubuntu 22.04 LTS first
wsl --install -d Ubuntu-22.04

# Then clone and run in WSL2
git clone <your-repo>
cd HomeAI
chmod +x install.sh scripts/*.sh cleanup.sh
./install.sh
```

**Note**: This installer is designed exclusively for Ubuntu 22.04 LTS. It will not work with other WSL2 distributions or other Linux distributions.

## Requirements

- **Operating System**: Ubuntu Server 22.04 LTS **ONLY**
  - Native Ubuntu Server 22.04 LTS installation, OR
  - WSL2 with Ubuntu 22.04 LTS on Windows
- NVIDIA GPU (RTX 2080 Ti class or better)
- 16GB+ RAM
- 50GB+ free disk space
- Internet connection for model downloads

**Note**: This installer is designed exclusively for Ubuntu 22.04 LTS. It will not work on other Linux distributions or operating systems.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Open WebUI    │    │   Router        │    │   Ollama        │
│   Port: 8080    │◄──►│   Port: 5001    │◄──►│   Port: 11434   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Nginx Proxy   │    │   STT Service   │    │   TTS Service   │
│   Port: 80/443  │    │   Port: 5002    │    │   Port: 5003    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Installation Options

### Interactive Mode (Default)
```bash
./install.sh
```
Prompts for configuration values with sensible defaults.

### Non-Interactive Mode
```bash
./install.sh --noninteractive
```
Uses existing configuration from `~/.local-ai-stack/config.env`.

### Reconfigure
```bash
./install.sh --reconfigure
```
Forces re-prompting for all configuration values.

### Vision Models
```bash
./install.sh --pull-vision
```
Also downloads vision-capable models.

### Backend Selection
```bash
./install.sh --stt-backend=docker --tts-backend=venv
```
Choose between `venv` (default) or `docker` for STT/TTS services.

## Configuration

All settings are stored in `~/.local-ai-stack/config.env`:

### Local-Only Setup (Recommended)
For most users, leave the domain blank during installation. All services will be accessible via:
- **WebUI**: http://localhost
- **Router API**: http://localhost/api/
- **STT Service**: http://localhost/stt/
- **TTS Service**: http://localhost/tts/

### Domain Setup (Optional)
If you want HTTPS and external access, configure a domain:
```bash
./install.sh --domain-ui=ai.example.com
```

**Domain Setup Requirements:**
1. **DNS Configuration**: Point your domain's A record to this server's IP address
2. **Port 80 Access**: Ensure port 80 is open on your firewall/router
3. **DNS Propagation**: Wait for DNS changes to propagate (can take up to 24 hours)
4. **SSL Certificates**: The installer will automatically generate Let's Encrypt certificates

**Example DNS Records:**
```
ai.example.com     A     YOUR_SERVER_IP
api.example.com    A     YOUR_SERVER_IP  (auto-generated)
```

**Troubleshooting Domain Issues:**
```bash
# Check domain resolution
nslookup ai.example.com

# Test connectivity
curl -I http://ai.example.com

# Run the troubleshooting script
./scripts/troubleshoot_letsencrypt.sh
```

```bash
# Server Configuration
SERVER_IP=192.168.1.100
DOMAIN_UI=ai.example.com
DOMAIN_API=api.example.com

# Service Ports
OLLAMA_PORT=11434
WEBUI_PORT=8080
ROUTER_PORT=5001
STT_PORT=5002
TTS_PORT=5003

# API Keys
TAVILY_API_KEY=your_tavily_key_here

# Model Selection
FRONT_MODEL=llama3:8b
BACK_MODEL=qwen2.5:14b-instruct
VISION_MODEL=qwen2.5-vl:7b-instruct
```

## Usage

### Starting Services
```bash
# Start all services
make up

# Start specific service
make up-ollama
make up-webui
make up-router
```

### Stopping Services
```bash
# Stop all services
make down

# Stop specific service
make down-webui
```

### Viewing Logs
```bash
# All services
make logs

# Specific service
make logs-router
```

### Health Checks
```bash
# Run health checks
./scripts/health_checks.sh
```

## Uninstallation

```bash
./cleanup.sh
```

Removes all containers, services, and optionally data volumes.

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**: If you get "Permission denied" errors:
   ```bash
   chmod +x scripts/*.sh
   chmod +x install.sh
   chmod +x cleanup.sh
   ```
   Then run: `./install.sh` (NOT with sudo)

2. **Docker Permission Errors**: If you get "permission denied while trying to connect to the Docker daemon":
   ```bash
   # Add your user to the docker group
   sudo usermod -aG docker $USER
   
   # Log out and back in, OR run this command:
   newgrp docker
   ```
   The installer will automatically add you to the docker group, but you may need to log out and back in.

3. **Docker Compose Version Warnings**: The installer now uses modern Docker Compose syntax without the obsolete `version` field.

4. **NVIDIA Container Toolkit**: Ensure NVIDIA drivers are installed
5. **Port Conflicts**: Check if ports are already in use
6. **Model Downloads**: Large models may take time; check disk space
7. **Firewall**: Ensure ports are open on your network
8. **Let's Encrypt Issues**: If certificate generation fails:
   - Ensure port 80 is open and accessible from the internet
   - Verify your domain points to this server's IP address
   - Check DNS propagation: `nslookup yourdomain.com`
   - Try staging first: `sudo certbot certonly --standalone -d yourdomain.com --staging`

### WSL2-Specific Issues

1. **WSL2 Version**: Ensure you're using WSL2, not WSL1
   ```bash
   wsl --set-version Ubuntu-22.04 2
   ```

2. **GPU Support**: WSL2 GPU support requires Windows 11 or Windows 10 21H2+
   - Install NVIDIA drivers on Windows
   - Install NVIDIA Container Toolkit in WSL2

3. **Memory Limits**: WSL2 may have memory limits. Add to `~/.wslconfig`:
   ```
   [wsl2]
   memory=16GB
   swap=8GB
   ```

4. **Port Forwarding**: WSL2 ports are not automatically accessible from Windows
   - Access services via `localhost:port` from Windows
   - Or configure port forwarding in WSL2

### Logs

- **Ollama**: `journalctl -u ollama -f`
- **Docker Services**: `docker compose logs -f`
- **Systemd Services**: `journalctl -u stt -f` or `journalctl -u tts -f`

### Reset Configuration

```bash
rm -rf ~/.local-ai-stack
./install.sh --reconfigure
```

## Development

### Project Structure
```
HomeAI/
├── install.sh              # Main installer
├── scripts/                # Modular installation scripts
├── ollama-webui/          # Open WebUI configuration
├── llama-router/          # Router service
├── voice/                 # STT/TTS services
├── systemd/               # Systemd service files
├── nginx/                 # Nginx configuration
└── Makefile               # Service management
```

### Adding New Models

1. Edit `~/.local-ai-stack/config.env`
2. Add model to `install_ollama.sh`
3. Re-run installer or manually pull: `ollama pull <model>`

## License

[Your License Here]

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues and questions:
- Check the troubleshooting section
- Review logs for error messages
- Open an issue with detailed information
