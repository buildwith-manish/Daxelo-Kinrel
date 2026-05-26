#!/bin/bash
cd /home/z/my-project
while true; do
  echo "[$(date)] Starting Bun server..." >> /tmp/kinrel-bun.log
  bun static-server.js >> /tmp/kinrel-bun.log 2>&1
  EXIT=$?
  echo "[$(date)] Server exited with code $EXIT, restarting in 1s..." >> /tmp/kinrel-bun.log
  sleep 1
done
