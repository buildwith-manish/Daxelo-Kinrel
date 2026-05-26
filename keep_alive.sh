#!/bin/bash
# Persistent Next.js server manager
cd /home/z/my-project

while true; do
  echo "[$(date +%T)] Starting Next.js..." >> /tmp/nextjs_manager.log
  npx next dev --port 3000 >> /tmp/nextjs_manager.log 2>&1
  echo "[$(date +%T)] Next.js died, restarting in 2s..." >> /tmp/nextjs_manager.log
  sleep 2
done
