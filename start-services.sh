#!/bin/bash
# Start kinship service
cd /home/z/my-project/mini-services/kinship-service
bun index.ts &
KINSHIP_PID=$!

# Start Next.js dev server
cd /home/z/my-project
npx next dev --port 3000 &
NEXT_PID=$!

echo "kinship PID: $KINSHIP_PID"
echo "next PID: $NEXT_PID"

# Keep alive
wait
