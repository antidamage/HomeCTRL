#!/bin/bash

# Router Setup Script
# Sets up intelligent model routing with auto-escalation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../install.sh" 2>/dev/null || true

CONFIG_FILE="$HOME/.local-ai-stack/config.env"
source "$CONFIG_FILE"

ROUTER_PORT=${ROUTER_PORT:-1338}
FRONT_MODEL=${FRONT_MODEL:-"llama3:8b"}
BACK_MODEL=${BACK_MODEL:-"qwen2.5:14b-instruct"}
TAVILY_KEY=${TAVILY_KEY:-""}

setup_router() {
    log_step "Setting up Router Service"
    
    cd "$HOME/llama-router"
    
    # Create requirements.txt
    cat > requirements.txt << EOF
fastapi==0.104.1
uvicorn[standard]==0.24.0
httpx==0.25.2
pydantic==2.5.0
python-multipart==0.0.6
pillow==10.1.0
pytesseract==0.3.10
tavily-python==0.3.1
python-dotenv==1.0.0
EOF

    # Create Dockerfile
    cat > Dockerfile << EOF
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \\
    tesseract-ocr \\
    tesseract-ocr-eng \\
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

EXPOSE ${ROUTER_PORT}

CMD ["uvicorn", "router:app", "--host", "0.0.0.0", "--port", "${ROUTER_PORT}"]
EOF

    # Create router.py
    cat > router.py << EOF
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
import httpx
import json
import logging
import re
from typing import Dict, Any, Optional
import os
from dotenv import load_dotenv

load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Router-Escalate", version="1.0.0")

# Configuration
OLLAMA_BASE_URL = "http://127.0.0.1:11434"
FRONT_MODEL = "${FRONT_MODEL}"
BACK_MODEL = "${BACK_MODEL}"
TAVILY_API_KEY = os.getenv("TAVILY_API_KEY", "${TAVILY_KEY}")

# Difficulty patterns
EASY_PATTERNS = [
    r"hello", r"hi", r"how are you", r"what is", r"explain simply",
    r"basic", r"simple", r"easy", r"quick", r"fast"
]

COMPLEX_PATTERNS = [
    r"research", r"analyze", r"compare", r"evaluate", r"critique",
    r"complex", r"detailed", r"comprehensive", r"thorough", r"deep"
]

SEARCH_PATTERNS = [
    r"latest", r"news", r"current", r"recent", r"today",
    r"search", r"find", r"look up", r"information about"
]

def determine_difficulty(prompt: str) -> str:
    """Determine if prompt should use front or back model"""
    prompt_lower = prompt.lower()
    
    # Check for search patterns first
    for pattern in SEARCH_PATTERNS:
        if re.search(pattern, prompt_lower):
            logger.info("SEARCHING... Pattern: %s", pattern)
            return "search"
    
    # Check for complex patterns
    for pattern in COMPLEX_PATTERNS:
        if re.search(pattern, prompt_lower):
            logger.info("ESCALATING... Pattern: %s", pattern)
            return "back"
    
    # Check for easy patterns
    for pattern in EASY_PATTERNS:
        if re.search(pattern, prompt_lower):
            logger.info("FRONT... Pattern: %s", pattern)
            return "front"
    
    # Default to front for unknown patterns
    logger.info("FRONT... Default pattern")
    return "front"

async def search_web(query: str) -> str:
    """Perform web search using Tavily"""
    if not TAVILY_API_KEY:
        return "Web search not available - no API key configured"
    
    try:
        from tavily import TavilyClient
        client = TavilyClient(api_key=TAVILY_API_KEY)
        response = client.search(query, search_depth="basic", max_results=3)
        
        results = []
        for result in response.get("results", []):
            results.append(f"Source: {result.get('url', 'N/A')}\\n{result.get('content', 'No content')}")
        
        return "\\n\\n".join(results) if results else "No search results found"
    except Exception as e:
        logger.error("Web search failed: %s", e)
        return f"Web search failed: {str(e)}"

async def call_ollama(model: str, prompt: str, system: str = "") -> str:
    """Call Ollama API"""
    try:
        async with httpx.AsyncClient() as client:
            payload = {
                "model": model,
                "prompt": prompt,
                "stream": False
            }
            if system:
                payload["system"] = system
            
            response = await client.post(
                f"{OLLAMA_BASE_URL}/api/generate",
                json=payload,
                timeout=300
            )
            response.raise_for_status()
            
            result = response.json()
            return result.get("response", "No response")
    except Exception as e:
        logger.error("Ollama call failed: %s", e)
        return f"Error calling Ollama: {str(e)}"

@app.get("/v1/models")
async def list_models():
    """List available models"""
    return {
        "object": "list",
        "data": [
            {
                "id": "router-escalate",
                "object": "model",
                "created": 1677610602,
                "owned_by": "router"
            }
        ]
    }

@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    """Handle chat completions with intelligent routing"""
    try:
        body = await request.json()
        messages = body.get("messages", [])
        stream = body.get("stream", False)
        
        if not messages:
            raise HTTPException(status_code=400, detail="No messages provided")
        
        # Get the last user message
        user_message = ""
        for msg in reversed(messages):
            if msg.get("role") == "user":
                user_message = msg.get("content", "")
                break
        
        if not user_message:
            raise HTTPException(status_code=400, detail="No user message found")
        
        # Determine difficulty and route accordingly
        difficulty = determine_difficulty(user_message)
        
        if difficulty == "search":
            # Web search + back model
            logger.info("SEARCHING... Performing web search")
            search_results = await search_web(user_message)
            enhanced_prompt = f"Based on the following information:\\n\\n{search_results}\\n\\nPlease answer: {user_message}"
            
            logger.info("ESCALATING... Using back model for search results")
            response = await call_ollama(BACK_MODEL, enhanced_prompt)
            
        elif difficulty == "back":
            # Use back model directly
            logger.info("ESCALATING... Using back model")
            response = await call_ollama(BACK_MODEL, user_message)
            
        else:
            # Use front model
            logger.info("FRONT... Using front model")
            response = await call_ollama(FRONT_MODEL, user_message)
        
        # Anti-echo: remove the original prompt if it appears in response
        if user_message.lower() in response.lower():
            response = response.replace(user_message, "").strip()
        
        if stream:
            # Streaming response
            async def generate():
                yield f"data: {json.dumps({'choices': [{'delta': {'content': response}}]})}\\n\\n"
                yield "data: [DONE]\\n\\n"
            
            return StreamingResponse(generate(), media_type="text/plain")
        else:
            # Non-streaming response
            return {
                "id": "chatcmpl-123",
                "object": "chat.completion",
                "created": 1677610602,
                "model": "router-escalate",
                "choices": [
                    {
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": response
                        },
                        "finish_reason": "stop"
                    }
                ],
                "usage": {
                    "prompt_tokens": len(user_message),
                    "completion_tokens": len(response),
                    "total_tokens": len(user_message) + len(response)
                }
            }
            
    except Exception as e:
        logger.error("Error in chat completions: %s", e)
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "router-escalate"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=${ROUTER_PORT})
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << EOF
version: '3.8'
services:
  router:
    build: .
    container_name: llama-router
    restart: unless-stopped
    network_mode: host
    environment:
      - TAVILY_API_KEY=${TAVILY_KEY}
    ports:
      - "127.0.0.1:${ROUTER_PORT}:${ROUTER_PORT}"
    volumes:
      - ./data:/app/data
EOF

    # Create .env file
    cat > .env << EOF
TAVILY_API_KEY=${TAVILY_KEY}
EOF

    # Build and start
    docker compose up -d --build
    
    log_success "Router service started on port $ROUTER_PORT"
}

main() {
    setup_router
}

main
