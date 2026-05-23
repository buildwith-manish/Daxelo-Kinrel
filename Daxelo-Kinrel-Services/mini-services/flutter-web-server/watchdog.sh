#!/bin/bash
cd /home/z/my-project/mini-services/flutter-web-server
while true; do
  bun index.ts 2>&1
  sleep 2
done
