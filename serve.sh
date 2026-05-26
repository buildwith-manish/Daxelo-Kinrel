#!/bin/bash
cd /home/z/my-project
while true; do
  echo "[$(date)] Starting..." >> /tmp/kinrel-serve.log
  npx next dev -p 3000 2>&1 | while IFS= read -r line; do
    echo "$line" >> /tmp/kinrel-serve.log
  done
  echo "[$(date)] Restarting in 1s..." >> /tmp/kinrel-serve.log
  sleep 1
done
