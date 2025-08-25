# Quick Start Guide

Get your local AI stack running in minutes!

## Prerequisites

- **Operating System**: Ubuntu Server 22.04 LTS **ONLY**
  - Native Ubuntu Server 22.04 LTS installation, OR
  - WSL2 with Ubuntu 22.04 LTS on Windows
- NVIDIA GPU (RTX 2080 Ti class or better)
- 16GB+ RAM
- 50GB+ free disk space
- Internet connection

**Note**: This installer is designed exclusively for Ubuntu 22.04 LTS. It will not work on other Linux distributions or operating systems.

## One-Line Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd HomeAI

# Make installer executable and run
chmod +x install.sh scripts/*.sh cleanup.sh
./install.sh
```

## What Gets Installed

1. **Ollama** - Local model hosting
2. **Open WebUI** - Modern web interface
3. **Router** - Intelligent model routing with auto-escalation
4. **STT** - Speech-to-text service
5. **TTS** - Text-to-speech service
6. **Nginx** - Reverse proxy with optional TLS

## Default Models

- **Front Model**: `llama3:8b` (fast, good for simple tasks)
- **Back Model**: `qwen2.5:14b-instruct` (powerful, good for complex tasks)
- **Optional Vision**: `qwen2.5-vl:7b-instruct`

## Access Your AI Stack

After installation, access your services at:

### Local Access (Recommended)
- **WebUI**: http://localhost
- **Router API**: http://localhost/api/
- **STT Service**: http://localhost/stt/
- **TTS Service**: http://localhost/tts/

### Direct Port Access
- **WebUI**: http://localhost:8080
- **Router API**: http://localhost:5001/v1
- **STT Service**: http://localhost:5002
- **TTS Service**: http://localhost:5003

### Domain Access (if configured)
If you configured domains during installation, you can also access via:
- **WebUI**: https://yourdomain.com
- **Router API**: https://api.yourdomain.com/v1

## Quick Commands

```bash
# Start all services
make up

# Stop all services
make down

# View logs
make logs

# Check status
make status

# Run health checks
make health
```

## Configuration

All settings are stored in `~/.local-ai-stack/config.env`

To reconfigure:
```bash
./install.sh --reconfigure
```

## Non-Interactive Installation

Use existing configuration:
```bash
./install.sh --noninteractive
```

## Vision Models

Include vision-capable models:
```bash
./install.sh --pull-vision
```

## Docker vs Virtual Environment

Choose backend for STT/TTS:
```bash
./install.sh --stt-backend=docker --tts-backend=venv
```

## Domain Setup

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

## Troubleshooting

### Common Issues

1. **Port conflicts**: Check if ports are already in use
2. **NVIDIA drivers**: Ensure NVIDIA drivers are installed
3. **Model downloads**: Large models may take time
4. **Firewall**: Ensure ports are open on your network

### Logs

- **Docker services**: `make logs`
- **Systemd services**: `sudo journalctl -u service-name -f`

### Reset

```bash
# Remove everything
./cleanup.sh

# Reinstall
./install.sh
```

## Next Steps

1. **Test the WebUI**: Open http://localhost
2. **Try the Router**: Chat with `router-escalate` model
3. **Test STT/TTS**: Use the health endpoints
4. **Optional**: Configure domains for HTTPS with Let's Encrypt
5. **Customize models**: Add your preferred models

## Support

- Check the troubleshooting section
- Review logs for error messages
- Open an issue with detailed information

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

Your AI stack is now ready to use! 🚀
