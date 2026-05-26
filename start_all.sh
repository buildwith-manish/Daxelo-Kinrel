#!/bin/bash
cd /home/z/my-project/Daxelo-Kinrel-App/build/web
python3 -m http.server 8080 &
FLUTTER_PID=$!

cd /home/z/my-project
while true; do
  npx next dev --port 3000
  echo "Next.js exited, restarting in 3s..."
  sleep 3
done
