#!/bin/bash

# OCR Clipboard — One-click startup script
# Double-click to launch server and open browser

set -e

# Get the script's directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

PORT=8080
URL="http://localhost:${PORT}"

if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi

# Check if port is already in use
if lsof -i :${PORT} > /dev/null 2>&1; then
    echo "Port ${PORT} is already in use. Server may already be running."
    echo "Opening ${URL}..."
else
    echo "Starting OCR server on ${URL}..."
    # Start uvicorn in background
    uvicorn server:app --reload --port ${PORT} &
    SERVER_PID=$!
    
    # Wait for server to be ready
    echo "Waiting for server to start..."
    for i in {1..15}; do
        if curl -s -o /dev/null -w "%{http_code}" "${URL}" | grep -q "200"; then
            break
        fi
        sleep 1
    done
fi

# Open browser
open "${URL}"
echo "Browser opened. Press Ctrl+C to stop the server."

# Wait for user to stop
wait $SERVER_PID 2>/dev/null || true
