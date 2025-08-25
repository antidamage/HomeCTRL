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

- **WebUI**: http://your-server-ip:8080
- **Router API**: http://your-server-ip:1338/v1
- **STT Service**: http://your-server-ip:5002
- **TTS Service**: http://your-server-ip:5003

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

Configure domain for HTTPS (Router API will use api.yourdomain.com automatically):
```bash
./install.sh --domain-ui=ai.example.com
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

1. **Test the WebUI**: Open http://your-server-ip:8080
2. **Try the Router**: Chat with `router-escalate` model
3. **Test STT/TTS**: Use the health endpoints
4. **Configure domains**: Set up HTTPS with Let's Encrypt
5. **Customize models**: Add your preferred models

## Support

- Check the troubleshooting section
- Review logs for error messages
- Open an issue with detailed information

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Open WebUI    │    │   Router        │    │   Ollama        │
│   Port: 8080    │◄──►│   Port: 1338    │◄──►│   Port: 11434   │
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
