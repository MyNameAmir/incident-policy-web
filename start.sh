#!/usr/bin/env bash
set -euo pipefail

echo "[start.sh] Starting deployment..."
PORT="${PORT:-10000}"
echo "[start.sh] PORT=${PORT}"

# ----------------------------
# 1) Start Reflex backend (internal only)
# ----------------------------
echo "[start.sh] Starting Reflex backend on 127.0.0.1:8000 (internal only)..."
reflex run --env prod --backend-only --backend-host 127.0.0.1 --backend-port 8000 > /tmp/reflex.log 2>&1 &
BACK_PID=$!

# Wait for backend to be reachable
echo "[start.sh] Waiting for backend..."
for i in {1..60}; do
  if curl -fsS "http://127.0.0.1:8000/ping" >/dev/null 2>&1; then
    echo "[start.sh] Backend is up."
    break
  fi
  sleep 1
done

if ! curl -fsS "http://127.0.0.1:8000/ping" >/dev/null 2>&1; then
  echo "[start.sh] Backend never became reachable."
  echo "------ /tmp/reflex.log (last 200 lines) ------"
  tail -n 200 /tmp/reflex.log || true
  kill "$BACK_PID" || true
  exit 1
fi

# ----------------------------
# 2) Find exported static dir
# ----------------------------
# Reflex export commonly writes to: .web/_static
# Some setups produce: .web/dist
STATIC_DIR=""
if [ -d ".web/_static" ]; then
  STATIC_DIR=".web/_static"
elif [ -d ".web/dist" ]; then
  STATIC_DIR=".web/dist"
elif [ -d ".web/build" ]; then
  STATIC_DIR=".web/build"
fi

if [ -z "${STATIC_DIR}" ]; then
  echo "[start.sh] Could not find exported static directory under .web."
  echo "[start.sh] Listing .web:"
  ls -la .web || true
  exit 1
fi

echo "[start.sh] Serving static from ${STATIC_DIR}"

# ----------------------------
# 3) Install Caddy (reliable download)
# ----------------------------
echo "[start.sh] Installing Caddy..."
if ! command -v caddy >/dev/null 2>&1; then
  curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=amd64" -o /tmp/caddy
  chmod +x /tmp/caddy
  export PATH="/tmp:$PATH"
  mv /tmp/caddy /tmp/caddy_bin
  ln -sf /tmp/caddy_bin /tmp/caddy
fi

# ----------------------------
# 4) Write Caddyfile (static + backend + websockets)
# ----------------------------
cat > Caddyfile <<EOF
:{$PORT}

# Serve the exported frontend
root * $STATIC_DIR
file_server

# Reflex backend endpoints (API + WebSocket event bus)
@reflex_backend path /_event* /_api* /ping* /health* /favicon.ico
reverse_proxy @reflex_backend 127.0.0.1:8000

# SPA fallback: if file not found, serve index.html
try_files {path} /index.html
EOF

echo "[start.sh] Caddyfile:"
cat Caddyfile

# ----------------------------
# 5) Run Caddy in foreground (so Render sees port open)
# ----------------------------
echo "[start.sh] Starting Caddy..."
exec caddy run --config Caddyfile --adapter caddyfile
