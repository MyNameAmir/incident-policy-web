#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-10000}"
echo "[start.sh] PORT=${PORT}"
echo "[start.sh] pwd=$(pwd)"

# 1) Start backend
echo "[start.sh] Starting Reflex backend on 127.0.0.1:8000..."
(reflex run --env prod --backend-only --backend-host 127.0.0.1 --backend-port 8000 > /tmp/reflex_backend.log 2>&1) &
BACK_PID=$!
echo "[start.sh] Backend PID=${BACK_PID}"

# Wait for backend port
python - <<'PY'
import socket, time, sys
deadline = time.time() + 90
while time.time() < deadline:
    s = socket.socket()
    s.settimeout(1)
    try:
        s.connect(("127.0.0.1", 8000))
        s.close()
        print("[start.sh] Backend port 8000 is open.")
        sys.exit(0)
    except Exception:
        time.sleep(1)
print("[start.sh] Backend never became reachable.")
sys.exit(1)
PY

# Quick ping (no pipes)
curl -sS http://127.0.0.1:8000/ping -o /dev/null && echo "[start.sh] /ping OK" || echo "[start.sh] /ping failed"

# 2) Static dir (THIS is the key fix)
STATIC_DIR=".web/build/client"
if [ ! -f "${STATIC_DIR}/index.html" ]; then
  echo "[start.sh] ERROR: ${STATIC_DIR}/index.html not found"
  echo "[start.sh] Searching for index.html under .web ..."
  find .web -maxdepth 6 -name "index.html" -print || true
  echo "[start.sh] Backend log tail:"
  tail -n 120 /tmp/reflex_backend.log || true
  exit 1
fi

echo "[start.sh] Serving static from ${STATIC_DIR}"
ls -la "${STATIC_DIR}/index.html"

# 3) Install Caddy (simple, reliable tar from official site)
echo "[start.sh] Installing Caddy..."
if ! command -v caddy >/dev/null 2>&1; then
  curl -fsSL https://caddyserver.com/api/download?os=linux\&arch=amd64 -o /tmp/caddy
  chmod +x /tmp/caddy
  export PATH="/tmp:$PATH"
fi
caddy version || true

echo "[start.sh] Writing Caddyfile with literal port: ${PORT}"

cat > Caddyfile <<EOF
{
  admin off
}

:${PORT}

root * .web/build/client
file_server

@reflex_backend path /_event* /_api* /ping* /health*
reverse_proxy @reflex_backend 127.0.0.1:8000

try_files {path} /index.html
EOF

echo "[start.sh] Caddyfile content (with line numbers):"
nl -ba Caddyfile

echo "[start.sh] Sanity check: show listen line:"
grep -nE '^\s*:' Caddyfile || true

echo "[start.sh] Checking for invalid brace syntax..."
if grep -nE '^\s*:\s*\{|\{\$' Caddyfile; then
  echo "[start.sh] ERROR: Invalid brace syntax in listen line."
  exit 1
fi

echo "[start.sh] Validating Caddyfile..."
caddy validate --config Caddyfile --adapter caddyfile || {
  echo "[start.sh] Caddy validation FAILED"
  echo "[start.sh] Dumping Caddyfile again:"
  cat Caddyfile
  exit 1
}

echo "[start.sh] Starting Caddy on port ${PORT}..."
exec caddy run --config Caddyfile --adapter caddyfile
