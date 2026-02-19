#!/usr/bin/env bash
set -euo pipefail

export PORT="${PORT:-10000}"
echo "[start.sh] PORT=$PORT"

# -----------------------
# Caddyfile
# -----------------------
cat > Caddyfile <<EOF
{
  admin off
}

:${PORT} {
  encode gzip

  root * .web
  file_server
  try_files {path} /index.html

  @backend path /_event* /_upload* /upload* /ping /_ping /api*
  reverse_proxy @backend 127.0.0.1:8000
}
EOF

# -----------------------
# Start Reflex BACKEND ONLY
# -----------------------
echo "[start.sh] Starting Reflex backend only..."
# IMPORTANT: no frontend build at runtime
reflex run --env prod --backend-only --backend-host 0.0.0.0 --backend-port 8000 > /tmp/reflex.log 2>&1 &

# Wait until backend is actually up
echo "[start.sh] Waiting for backend..."
for i in $(seq 1 120); do
  if curl -fsS "http://127.0.0.1:8000/ping" >/dev/null 2>&1; then
    echo "[start.sh] Backend is up."
    break
  fi
  sleep 1
  if [ "$i" -eq 120 ]; then
    echo "[start.sh] Backend never became reachable."
    echo "------ /tmp/reflex.log (last 300 lines) ------"
    tail -n 300 /tmp/reflex.log || true
    echo "---------------------------------------------"
    exit 1
  fi
done

# -----------------------
# Get Caddy
# -----------------------
if [ ! -x ./caddy ]; then
  echo "[start.sh] Downloading caddy..."
  curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=amd64" -o ./caddy
  chmod +x ./caddy
fi

echo "[start.sh] Starting Caddy..."
exec ./caddy run --config Caddyfile --adapter caddyfile
