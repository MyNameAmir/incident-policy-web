#!/usr/bin/env bash
set -euo pipefail

echo "[start.sh] Starting deployment..."
echo "[start.sh] pwd=$(pwd)"
echo "[start.sh] ls -la:"
ls -la

PORT="${PORT:-10000}"
echo "[start.sh] PORT=${PORT}"

# --- 1) Start Reflex backend (internal only) ---
echo "[start.sh] Starting Reflex backend on 127.0.0.1:8000 (internal only)..."
# Capture reflex logs to a file for debugging
(reflex run --env prod --backend-only --backend-host 127.0.0.1 --backend-port 8000 > /tmp/reflex_backend.log 2>&1) &
BACK_PID=$!

echo "[start.sh] Backend PID=$BACK_PID"
echo "[start.sh] Waiting for backend port 8000 to accept connections..."
python - <<'PY'
import socket, time, sys
host, port = "127.0.0.1", 8000
deadline = time.time() + 90
while time.time() < deadline:
    s = socket.socket()
    s.settimeout(1)
    try:
        s.connect((host, port))
        s.close()
        print("[start.sh] Backend port is open.")
        sys.exit(0)
    except Exception:
        time.sleep(1)
print("[start.sh] Backend never became reachable on 127.0.0.1:8000")
sys.exit(1)
PY

echo "[start.sh] Backend health check:"
curl -sS -o /dev/null -w "[start.sh] GET /ping -> %{http_code}\n" http://127.0.0.1:8000/ping || true
curl -sS -o /dev/null -w "[start.sh] GET /health -> %{http_code}\n" http://127.0.0.1:8000/health || true

# --- 2) Diagnose Reflex web export output paths ---
echo "[start.sh] Checking .web directory..."
if [ -d ".web" ]; then
  echo "[start.sh] .web exists. Tree (depth 3):"
  find .web -maxdepth 3 -type d -print | sed 's/^/[start.sh]   /'
  echo "[start.sh] .web files (top 50):"
  find .web -maxdepth 4 -type f | head -n 50 | sed 's/^/[start.sh]   /'
else
  echo "[start.sh] ERROR: .web directory not found at runtime."
fi

# --- 3) Pick the correct static output directory automatically ---
# We look for index.html in common export folders.
STATIC_DIR=""
for cand in \
  ".web/build" \
  ".web/_static" \
  ".web/dist" \
  ".web/build/client" \
  ".web/client" \
  ".web/public"
do
  if [ -f "${cand}/index.html" ]; then
    STATIC_DIR="${cand}"
    break
  fi
done

if [ -z "${STATIC_DIR}" ]; then
  echo "[start.sh] ERROR: Could not find index.html under .web in known locations."
  echo "[start.sh] Searching for index.html anywhere under .web (up to depth 6)..."
  find .web -maxdepth 6 -name "index.html" -print || true
  echo "[start.sh] Last 200 lines of backend log (in case it explains missing export):"
  tail -n 200 /tmp/reflex_backend.log || true
  exit 1
fi

echo "[start.sh] Using STATIC_DIR=${STATIC_DIR}"
echo "[start.sh] index.html exists:"
ls -la "${STATIC_DIR}/index.html"

# --- 4) Install Caddy (reliable) ---
echo "[start.sh] Installing Caddy..."
if ! command -v caddy >/dev/null 2>&1; then
  # Use official install script (much more reliable than random tar URLs)
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /tmp/caddy.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /tmp/caddy.list
  # We may not have apt on Render containers; fallback to direct binary if apt missing.
  if command -v apt-get >/dev/null 2>&1; then
    sudo mkdir -p /usr/share/keyrings || true
    sudo mv /tmp/caddy.gpg /usr/share/keyrings/caddy-stable-archive-keyring.gpg || true
    sudo mv /tmp/caddy.list /etc/apt/sources.list.d/caddy-stable.list || true
    sudo apt-get update -y
    sudo apt-get install -y caddy
  else
    echo "[start.sh] apt-get not available; downloading caddy binary..."
    # Try GitHub release binary (stable)
    curl -L -o /tmp/caddy.tar.gz https://github.com/caddyserver/caddy/releases/latest/download/caddy_2.8.4_linux_amd64.tar.gz
    tar -xzf /tmp/caddy.tar.gz -C /tmp
    chmod +x /tmp/caddy
    export PATH="/tmp:$PATH"
  fi
fi

echo "[start.sh] caddy version:"
caddy version || true

# --- 5) Write Caddyfile (admin OFF, serve static, reverse proxy backend endpoints + websocket) ---
cat > Caddyfile <<CADDY
{
  admin off
}

:{$PORT}

# Serve exported frontend
root * ${STATIC_DIR}
file_server

# Reflex backend endpoints (API + event WebSocket)
@reflex_backend path /_event* /_api* /ping* /health*
reverse_proxy @reflex_backend 127.0.0.1:8000

# SPA fallback
try_files {path} /index.html
CADDY

echo "[start.sh] Caddyfile:"
sed 's/^/[start.sh] /' Caddyfile

echo "[start.sh] Sanity check: list static dir top-level:"
ls -la "${STATIC_DIR}" | head -n 200 | sed 's/^/[start.sh] /'

# --- 6) Start Caddy (foreground) ---
echo "[start.sh] Starting Caddy on :${PORT}..."
exec caddy run --config Caddyfile --adapter caddyfile
