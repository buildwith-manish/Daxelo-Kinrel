#!/bin/bash
# Server manager that keeps Next.js alive
LOG="/home/z/my-project/dev.log"

while true; do
  echo "[$(date +%T)] Starting Next.js dev server..." >> "$LOG"
  cd /home/z/my-project && npx next dev --port 3000 >> "$LOG" 2>&1
  EXIT_CODE=$?
  echo "[$(date +%T)] Next.js exited with code $EXIT_CODE, restarting in 2s..." >> "$LOG"
  sleep 2
done
