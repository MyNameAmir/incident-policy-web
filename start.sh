#!/usr/bin/env bash
set -euo pipefail

: "${PORT:=10000}"

# Where Reflex export puts the static frontend
FRONTEND_DIR=".web/build/client"

if [ ! -f "${FRONTEND_DIR}/index.html" ]; then
  echo "ERROR: ${FRONTEND_DIR}/index.html not found."
  echo "Did the build command run: reflex export --frontend-only --no-zip ?"
  ls -la .web || true
  ls -la "${FRONTEND_DIR}" || true
  exit 1
fi

# Start Reflex backend on localhost only (internal)
reflex run --env prod --backend-only --backend-host 127.0.0.1 --backend-port 8000 &
BACK_PID=$!

# Download Caddy (no root needed)
CADDY_DIR=".caddybin"
mkdir -p "${CADDY_DIR}"
if [ ! -x "${CADDY_DIR}/caddy" ]; then
  echo "Downloading caddy..."
  curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=amd64" -o "${CADDY_DIR}/caddy"
  chmod +x "${CADDY_DIR}/caddy"
fi

# Caddyfile: serve static frontend + proxy Reflex backend endpoints
cat > Caddyfile <<EOF
:${PORT} {
  encode gzip

  root * ${FRONTEND_DIR}
  file_server

  # Reflex event/websocket endpoints (proxy to backend)
  reverse_proxy /_event* 127.0.0.1:8000
  reverse_proxy /_upload* 127.0.0.1:8000
  reverse_proxy /ping 127.0.0.1:8000

  # SPA fallback to index.html
  try_files {path} {path}/ /index.html
}
EOF

exec "${CADDY_DIR}/caddy" run --config Caddyfile
