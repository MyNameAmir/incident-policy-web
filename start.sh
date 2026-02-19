#!/usr/bin/env bash
set -euo pipefail

export PORT="${PORT:-10000}"
echo "[start.sh] PORT=$PORT"

# ---- Find where index.html actually is ----
echo "[start.sh] Locating exported frontend (index.html)..."
INDEX_PATH="$(find . -maxdepth 4 -type f -name index.html 2>/dev/null | head -n 1 || true)"

if [ -z "$INDEX_PATH" ]; then
  echo "[start.sh] ERROR: index.html not found. Your build step did not export the frontend."
  echo "[start.sh] Listing top-level directories:"
  ls -la
  echo "[start.sh] Listing .web (if present):"
  ls -la .web || true
  exit 1
fi

FRONTEND_DIR="$(dirname "$INDEX_PATH")"
echo "[start.sh] Using FRONTEND_DIR=$FRONTEND_DIR"

# ---- Write Caddyfile ----
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

# ---- Start Reflex backend only ----
echo "[start.sh] Starting Reflex backend only..."
reflex run --env prod --backend-only --backend-host 0.0.0.0 --backend-port 8000 > /tmp/reflex.log 2>&1 &

echo "[start.sh] Waiting for backend..."
for i in $(seq 1 120); do
  if curl -fsS "http://127.0.0.1:8000/ping" >/dev/null 2>&1; then
    echo "[start.sh] Backend is up."
    break
  fi
  sleep 1
  if [ "$i" -eq 120 ]; then
    echo "[start.sh] Backend never became reachable."
    tail -n 300 /tmp/reflex.log || true
    exit 1
  fi
done

# ---- Download caddy binary ----
if [ ! -x ./caddy ]; then
  echo "[start.sh] Downloading caddy..."
  curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=amd64" -o ./caddy
  chmod +x ./caddy
fi

echo "[debug] pwd=$(pwd)"
echo "[debug] ls -la"
ls -la
echo "[debug] ls -la .web || true"
ls -la .web || true
echo "[debug] find index.html (maxdepth 6)"
find . -maxdepth 6 -name index.html -print || true


echo "[start.sh] Starting Caddy..."
exec ./caddy run --config Caddyfile --adapter caddyfile
