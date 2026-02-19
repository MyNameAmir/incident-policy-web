#!/usr/bin/env bash
set -euo pipefail

echo "[start.sh] Starting deployment..."

export PORT="${PORT:-10000}"
echo "[start.sh] Using public PORT=$PORT"

# ---- Write Caddyfile dynamically ----
cat > Caddyfile <<EOF
{
  admin off
}

:${PORT} {
  encode gzip

  # Serve Reflex static frontend (exported)
  root * .web
  file_server
  try_files {path} /index.html

  # Proxy Reflex backend (websocket + api)
  @backend path /_event* /_upload* /upload* /ping /_ping /api*
  reverse_proxy @backend 127.0.0.1:8000
}
EOF

echo "[start.sh] Caddyfile created"

# ---- Start Reflex backend ----
echo "[start.sh] Starting Reflex backend..."
reflex run --env prod --backend-host 127.0.0.1 --backend-port 8000 >/tmp/reflex.log 2>&1 &

# ---- Download Caddy binary reliably (no tar/gzip) ----
if [ ! -x ./caddy ]; then
  echo "[start.sh] Downloading caddy binary..."
  curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=amd64" -o ./caddy
  chmod +x ./caddy
fi

# ---- Start Caddy (public server) ----
echo "[start.sh] Starting Caddy..."
exec ./caddy run --config Caddyfile --adapter caddyfile
