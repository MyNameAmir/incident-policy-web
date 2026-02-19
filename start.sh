#!/usr/bin/env bash
set -euo pipefail

: "${PORT:=10000}"

FRONTEND_DIR=".web/build/client"

if [ ! -f "${FRONTEND_DIR}/index.html" ]; then
  echo "ERROR: ${FRONTEND_DIR}/index.html not found."
  echo "Make sure Render Build Command is:"
  echo "  pip install -r requirements.txt && reflex export --frontend-only --no-zip"
  ls -la .web || true
  ls -la "${FRONTEND_DIR}" || true
  exit 1
fi

# Start Reflex backend internally
reflex run --env prod --backend-only --backend-host 127.0.0.1 --backend-port 8000 &
BACK_PID=$!

# Download Caddy
CADDY_DIR=".caddybin"
mkdir -p "${CADDY_DIR}"
if [ ! -x "${CADDY_DIR}/caddy" ]; then
  echo "Downloading caddy..."
  curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=amd64" -o "${CADDY_DIR}/caddy"
  chmod +x "${CADDY_DIR}/caddy"
fi

# Write Caddyfile
cat > Caddyfile <<EOF
{
  # Prevent public access to Caddy's admin API (fixes 403 host not allowed spam)
  admin off
}

:${PORT} {
  encode gzip

  # Serve exported Reflex frontend (SPA)
  root * ${FRONTEND_DIR}
  try_files {path} {path}/ /index.html
  file_server

  # Proxy Reflex backend endpoints (including WebSocket)
  @event path /_event*
  reverse_proxy @event 127.0.0.1:8000 {
    header_up Host {host}
    header_up X-Forwarded-Host {host}
    header_up X-Forwarded-Proto {scheme}
    header_up X-Forwarded-For {remote_host}
  }

  @api path /_upload* /ping
  reverse_proxy @api 127.0.0.1:8000 {
    header_up Host {host}
    header_up X-Forwarded-Host {host}
    header_up X-Forwarded-Proto {scheme}
    header_up X-Forwarded-For {remote_host}
  }
}
EOF

exec "${CADDY_DIR}/caddy" run --config Caddyfile
