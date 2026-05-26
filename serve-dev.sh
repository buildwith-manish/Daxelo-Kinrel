#!/bin/bash
cd /home/z/my-project
export DATABASE_URL="file:./db/custom.db"
trap '' SIGHUP SIGINT SIGTERM
while true; do
  echo "[$(date +%T)] Starting KINREL Dev Server..." >> /home/z/my-project/dev.log
  node ./node_modules/.bin/next dev -p 3000 >> /home/z/my-project/dev.log 2>&1
  echo "[$(date +%T)] Server exited, restarting in 3s..." >> /home/z/my-project/dev.log
  sleep 3
done
