#!/bin/bash
flutter build apk \
  --dart-define=APP_ENV=prod \
  --dart-define=FLAVOR=prod \
  --split-per-abi \
  --obfuscate \
  --split-debug-info=build/debug-info \
  --release
