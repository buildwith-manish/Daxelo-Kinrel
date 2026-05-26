#!/bin/bash
cd /home/z/my-project
while true; do
  echo "[$(date)] Starting next start..." >> /tmp/kinrel-prod.log
  node .next/standalone/server.js 2>&1 | while IFS= read -r line; do
    echo "$line" >> /tmp/kinrel-prod.log
  done
  echo "[$(date)] Server exited, restarting in 3s..." >> /tmp/kinrel-prod.log
  sleep 3
done
