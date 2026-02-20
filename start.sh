#!/usr/bin/env bash
set -euo pipefail

export PORT="${PORT:-10000}"
echo "[start.sh] PORT=$PORT"

# --- ensure frontend exists (optional but helpful) ---
if [ ! -d ".web" ]; then
  echo "[start.sh] ERROR: .web folder not found. Did you run 'reflex export --no-zip' in build?"
  ls -la
  exit 1
fi

# --- write Caddyfile (single public port) ---
cat > Caddyfile <<EOF
{
  admin off
}

:${PORT} {
  encode gzip

  # Serve the Reflex exported frontend
  root * .web
  file_server
  try_files {path} /index.html

  # Proxy Reflex websocket + API calls to backend (internal only)
  @backend path /_event* /_upload* /upload* /ping /_ping /api*
  reverse_proxy @backend 127.0.0.1:8000
}
EOF

# --- start Reflex backend on localhost ONLY (important) ---
echo "[start.sh] Starting Reflex backend on 127.0.0.1:8000 (internal only)..."
reflex run --env prod --backend-only --backend-host 127.0.0.1 --backend-port 8000 > /tmp/reflex.log 2>&1 &

# Wait for backend
echo "[start.sh] Waiting for backend..."
for i in $(seq 1 120); do
  if curl -fsS "http://127.0.0.1:8000/ping" >/dev/null 2>&1; then
    echo "[start.sh] Backend is up."
    break
  fi
  sleep 1
  if [ "$i" -eq 120 ]; then
    echo "[start.sh] Backend never became reachable."
    tail -n 200 /tmp/reflex.log || true
    exit 1
  fi
done

# --- download caddy if needed ---
if [ ! -x ./caddy ]; then
  echo "[start.sh] Downloading caddy..."
  curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=amd64" -o ./caddy
  chmod +x ./caddy
fi

echo "[start.sh] Starting Caddy..."
exec ./caddy run --config Caddyfile --adapter caddyfile
