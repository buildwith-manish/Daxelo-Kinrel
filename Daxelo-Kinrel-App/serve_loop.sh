#!/bin/bash
trap '' SIGHUP SIGINT SIGTERM

while true; do
  bun run /home/z/my-project/Daxelo-Kinrel-App/bun_serve_8080.ts 2>/dev/null
  sleep 1
done
