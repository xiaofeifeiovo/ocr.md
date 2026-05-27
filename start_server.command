#!/bin/bash

# OCR Clipboard — One-click startup script
# Double-click to launch server and open browser

set -e

# Get the script's directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

DEFAULT_PORT=8080
PORT="${1:-${PORT:-$DEFAULT_PORT}}"

port_in_use() {
    lsof -nP -iTCP:"$1" -sTCP:LISTEN > /dev/null 2>&1
}

find_available_port() {
    local port="$1"
    while port_in_use "$port"; do
        if [ "$port" -ge 65535 ]; then
            echo "No available port found." >&2
            return 1
        fi
        port=$((port + 1))
    done
    echo "$port"
}

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "Invalid port: ${PORT}"
    echo "Usage: ./start_server.command [port]"
    exit 1
fi

REQUESTED_PORT="$PORT"
PORT="$(find_available_port "$PORT")"
URL="http://localhost:${PORT}"

if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi

# Start a new server. If the requested port is busy, use the next free port.
if [ "$PORT" != "$REQUESTED_PORT" ]; then
    echo "Port ${REQUESTED_PORT} is already in use. Using ${PORT} instead."
fi

echo "Starting OCR server on ${URL}..."
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

if ! curl -s -o /dev/null -w "%{http_code}" "${URL}" | grep -q "200"; then
    echo "Server did not become ready on ${URL}."
    kill "$SERVER_PID" 2>/dev/null || true
    exit 1
fi

# Open browser
open "${URL}"
echo "Browser opened. Press Ctrl+C to stop the server."

# Wait for user to stop
wait $SERVER_PID 2>/dev/null || true
