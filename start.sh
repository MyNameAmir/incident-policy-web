#!/usr/bin/env bash
set -euo pipefail

echo "[start.sh] Starting deployment..."
export PORT="${PORT:-10000}"
echo "[start.sh] PORT=$PORT"

echo "[start.sh] Starting Reflex backend on 127.0.0.1:8000 (internal only)..."
reflex run --env prod --backend-only --backend-host 127.0.0.1 --backend-port 8000 >/tmp/reflex.log 2>&1 &
BACK_PID=$!

echo "[start.sh] Waiting for backend port 8000 to accept connections..."
python - <<'PY'
import socket, time, sys
for _ in range(60):
    s = socket.socket()
    try:
        s.connect(("127.0.0.1", 8000))
        print("[start.sh] Backend port is open.")
        sys.exit(0)
    except Exception:
        time.sleep(1)
    finally:
        s.close()
print("[start.sh] Backend never became reachable.")
sys.exit(1)
PY

echo "[start.sh] Serving static from .web/build"

echo "[start.sh] Installing Caddy..."
curl -fsSL https://caddyserver.com/api/download?os=linux\&arch=amd64 -o /tmp/caddy
chmod +x /tmp/caddy

cat > Caddyfile <<'CADDY'
:{$PORT}
root * .web/build
file_server

@reflex_backend path /_event* /_api* /ping* /health*
reverse_proxy @reflex_backend 127.0.0.1:8000

try_files {path} /index.html
CADDY

echo "[start.sh] Caddyfile:"
cat Caddyfile

echo "[start.sh] Starting Caddy on :$PORT..."
exec /tmp/caddy run --config Caddyfile --adapter caddyfile
