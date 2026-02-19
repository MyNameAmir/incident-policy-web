#!/usr/bin/env bash
set -euo pipefail

echo "[start.sh] Starting deployment..."
export PORT="${PORT:-10000}"
echo "[start.sh] Public PORT=$PORT"

# Where your exported frontend is. If your export uses a different folder,
# change this to ".web/build/client"
FRONTEND_DIR=".web"

# ---- Write Caddyfile dynamically ----
cat > Caddyfile <<EOF
{
  admin off
}

:${PORT} {
  encode gzip

  root * ${FRONTEND_DIR}
  file_server
  try_files {path} /index.html

  @backend path /_event* /_upload* /upload* /ping /_ping /api*
  reverse_proxy @backend 127.0.0.1:8000
}
EOF
echo "[start.sh] Caddyfile created"

# ---- Start Reflex backend (bind to 0.0.0.0) ----
echo "[start.sh] Starting Reflex backend on 0.0.0.0:8000..."
reflex run --env prod --backend-host 0.0.0.0 --backend-port 8000 >/tmp/reflex.log 2>&1 &

# ---- Wait for backend to be reachable ----
echo "[start.sh] Waiting for backend to be ready..."
for i in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:8000/ping" >/dev/null 2>&1; then
    echo "[start.sh] Backend is up."
    break
  fi
  sleep 1
  if [ "$i" -eq 60 ]; then
    echo "[start.sh] ERROR: Backend never became reachable on 127.0.0.1:8000"
    echo "------ Reflex log (last 200 lines) ------"
    tail -n 200 /tmp/reflex.log || true
    echo "----------------------------------------"
    exit 1
  fi
done

# ---- Download Caddy binary reliably ----
if [ ! -x ./caddy ]; then
  echo "[start.sh] Downloading caddy binary..."
  curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=amd64" -o ./caddy
  chmod +x ./caddy
fi

# ---- Start Caddy ----
echo "[start.sh] Starting Caddy..."
exec ./caddy run --config Caddyfile --adapter caddyfile
