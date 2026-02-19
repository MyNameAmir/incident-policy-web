#!/usr/bin/env bash
set -euo pipefail

export PORT="${PORT:-10000}"
echo "[start.sh] PORT=$PORT"

# --- Write Caddyfile ---
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

echo "[start.sh] Starting Reflex backend..."
# Start backend and log everything
reflex run --env prod --backend-host 0.0.0.0 --backend-port 8000 > /tmp/reflex.log 2>&1 &
BACK_PID=$!

# If Reflex dies quickly, print logs and exit
sleep 2
if ! kill -0 "$BACK_PID" 2>/dev/null; then
  echo "[start.sh] Reflex backend exited immediately."
  echo "------ /tmp/reflex.log (last 400 lines) ------"
  tail -n 400 /tmp/reflex.log || true
  echo "---------------------------------------------"
  exit 1
fi

echo "[start.sh] Waiting for backend /ping..."
for i in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:8000/ping" >/dev/null 2>&1; then
    echo "[start.sh] Backend is reachable."
    break
  fi
  sleep 1
  if [ "$i" -eq 60 ]; then
    echo "[start.sh] Backend never became reachable."
    echo "------ /tmp/reflex.log (last 400 lines) ------"
    tail -n 400 /tmp/reflex.log || true
    echo "---------------------------------------------"
    # Also show running processes for debugging
    ps aux | head -n 30 || true
    exit 1
  fi
done

# --- Get Caddy ---
if [ ! -x ./caddy ]; then
  echo "[start.sh] Downloading caddy..."
  curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=amd64" -o ./caddy
  chmod +x ./caddy
fi

echo "[start.sh] Starting Caddy..."
exec ./caddy run --config Caddyfile --adapter caddyfile
