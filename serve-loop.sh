#!/bin/bash
# DAXELO KINREL — Production NestJS auto-restart

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/Daxelo-Kinrel-Server"

# Load .env
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
fi

# Trap signals — keep running
trap 'echo "[$(date +%T)] Signal received, continuing..."' \
  SIGHUP SIGINT SIGTERM SIGUSR1 SIGUSR2

# Build first if dist/ doesn't exist
if [ ! -d "dist" ]; then
  echo "[$(date +%T)] Building NestJS app..."
  npm run build
fi

while true; do
  echo "[$(date +%T)] Starting KINREL NestJS Server..."
  node dist/main.js
  echo "[$(date +%T)] Server exited ($?), restarting in 3s..."
  sleep 3
done
