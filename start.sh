#!/usr/bin/env bash
set -euo pipefail

# Render provides $PORT
: "${PORT:=3000}"

# Start Reflex backend only (no Vite dev server)
# If your reflex version doesn't support --backend-only, see note below.
reflex run --env prod --backend-only --backend-port 8000 &
BACK_PID=$!

# Pick the static export directory (varies by Reflex versions)
if [ -d ".web/_static" ]; then
  FRONTEND_DIR=".web/_static"
elif [ -d ".web/build/client" ]; then
  FRONTEND_DIR=".web/build/client"
else
  echo "ERROR: Cannot find exported frontend directory under .web/"
  echo "Expected .web/_static or .web/build/client"
  exit 1
fi

# Install a tiny Node static server (lighter than Vite dev server)
# (You already have node available since Reflex uses it for frontend build steps)
npx --yes serve -s "$FRONTEND_DIR" -l "0.0.0.0:${PORT}" &
FRONT_PID=$!

# Keep container alive
wait $BACK_PID $FRONT_PID
