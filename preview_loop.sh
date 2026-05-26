#!/bin/bash
cd /home/z/my-project
trap '' SIGHUP SIGINT SIGTERM

while true; do
  npx next dev --port 3000 2>&1
  sleep 1
done
