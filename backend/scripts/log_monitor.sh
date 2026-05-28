#!/bin/bash
# DAXELO KINREL — Log Monitor Script
# Tails the application log output and filters for ERROR/FATAL lines.
# Pino uses numeric log levels: 40=warn, 50=error, 60=fatal

LOG_DIR="$(dirname "$0")/../logs"
mkdir -p "$LOG_DIR"

echo "🔍 Monitoring logs for ERROR and FATAL entries..."
echo "   Errors will be saved to: $LOG_DIR/errors.log"
echo "   Press Ctrl+C to stop"
echo ""

node dist/main.js 2>&1 | while IFS= read -r line; do
  echo "$line"
  # Check if the line contains error (level 50) or fatal (level 60)
  if echo "$line" | grep -qE '"level":(50|60)'; then
    echo "$line" >> "$LOG_DIR/errors.log"
  fi
done
