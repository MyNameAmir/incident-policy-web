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

# ----------------------------
# 2) Wait for backend TCP port 8000 (NOT /ping)
# ----------------------------
echo "[start.sh] Waiting for backend port 8000 to accept connections..."
python - <<'PY'
import socket, time, sys

host, port = "127.0.0.1", 8000
deadline = time.time() + 90  # seconds
while time.time() < deadline:
    s = socket.socket()
    s.settimeout(1.0)
    try:
        s.connect((host, port))
        s.close()
        print("[start.sh] Backend port is open.")
        sys.exit(0)
    except Exception:
        time.sleep(1)
    finally:
        try: s.close()
        except: pass

print("[start.sh] Backend never opened port 8000.")
sys.exit(1)
PY

# If the python check failed, print logs and exit
if ! python -c "import socket; s=socket.socket(); s.settimeout(1); s.connect(('127.0.0.1',8000)); s.close()" >/dev/null 2>&1; then
  echo "[start.sh] Backend not reachable. Showing last 200 lines of /tmp/reflex.log:"
  tail -n 200 /tmp/reflex.log || true
  kill "$BACK_PID" || true
  exit 1
fi

# ----------------------------
# 3) Find exported static dir (after reflex export in build step)
# ----------------------------
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
# 4) Install Caddy (reliable single-binary download)
# ----------------------------
echo "[start.sh] Installing Caddy..."
if ! command -v caddy >/dev/null 2>&1; then
  curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=amd64" -o /tmp/caddy
  chmod +x /tmp/caddy
  export PATH="/tmp:$PATH"
fi

# ----------------------------
# 5) Write Caddyfile (static + backend + websockets)
# ----------------------------
cat > Caddyfile <<EOF
:{$PORT}

# Serve exported frontend
root * $STATIC_DIR
file_server

# Reflex backend endpoints (API + event WebSocket)
@reflex_backend path /_event* /_api* /ping* /health* /favicon.ico
reverse_proxy @reflex_backend 127.0.0.1:8000

# SPA fallback
try_files {path} /index.html
EOF

echo "[start.sh] Caddyfile:"
cat Caddyfile

# ----------------------------
# 6) Run Caddy in foreground (Render needs this)
# ----------------------------
echo "[start.sh] Starting Caddy on :${PORT}..."
exec caddy run --config Caddyfile --adapter caddyfile
