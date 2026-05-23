#!/bin/bash
# KINREL Mirror - Auto-restart production server with signal trapping
cd /home/z/my-project
export DATABASE_URL="file:./db/custom.db"

# Trap all possible signals
trap 'echo "[$(date +%T)] Received signal, ignoring..." >> /home/z/my-project/dev.log' SIGHUP SIGINT SIGTERM SIGUSR1 SIGUSR2

while true; do
  echo "[$(date +%T)] Starting KINREL Mirror..." >> /home/z/my-project/dev.log
  node ./node_modules/.bin/next start -p 3000 >> /home/z/my-project/dev.log 2>&1
  echo "[$(date +%T)] Server exited with code $?, restarting in 3s..." >> /home/z/my-project/dev.log
  sleep 3
done
