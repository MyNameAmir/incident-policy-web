#!/usr/bin/env bash
set -euo pipefail

: "${PORT:=3000}"

# Start Reflex backend only on an internal port
reflex run --env prod --backend-only --backend-host 0.0.0.0 --backend-port 8000 &
BACK_PID=$!

# Find exported frontend directory
if [ -d ".web/_static" ]; then
  FRONTEND_DIR=".web/_static"
elif [ -d ".web/build/client" ]; then
  FRONTEND_DIR=".web/build/client"
else
  echo "ERROR: Cannot find exported frontend directory under .web/"
  echo "Expected .web/_static or .web/build/client"
  exit 1
fi

# Serve frontend on Render's public port
npx --yes serve -s "$FRONTEND_DIR" -l "${PORT}" &
FRONT_PID=$!

wait $BACK_PID $FRONT_PID
