#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

trap 'echo "[$(date +%T)] Signal received, continuing..."' \
  SIGHUP SIGINT SIGTERM SIGUSR1 SIGUSR2

while true; do
  echo "[$(date +%T)] Starting Next.js dev server on :3000..."
  npx next dev --port 3000
  echo "[$(date +%T)] Next.js exited ($?), restarting in 3s..."
  sleep 3
done
