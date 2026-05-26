#!/bin/bash
cd /home/z/my-project
export DATABASE_URL="file:./db/custom.db"
export NEXT_TELEMETRY_DISABLED=1

# Clear old log
> /home/z/my-project/dev.log

while true; do
  echo "[$(date +%T)] Starting Next.js..." >> /home/z/my-project/dev.log
  node ./node_modules/.bin/next dev --turbopack -p 3000 >> /home/z/my-project/dev.log 2>&1
  echo "[$(date +%T)] Next.js exited (code $?), restarting in 2s..." >> /home/z/my-project/dev.log
  sleep 2
done
