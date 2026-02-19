#!/usr/bin/env bash
set -euo pipefail

echo "[start.sh] Starting deployment..."

# Render provides this automatically
export PORT="${PORT:-10000}"

echo "[start.sh] Using public PORT=$PORT"

############################################
# 1. Write Caddyfile dynamically
############################################

cat > Caddyfile <<EOF
{
    # Disable admin API to prevent "host not allowed" errors
    admin off
}

:$PORT {

    encode gzip

    # Serve Reflex frontend static build
    root * .web
    file_server

    # SPA routing support
    try_files {path} /index.html

    # Proxy Reflex backend (including websocket)
    @backend {
        path /_event* /ping /_ping /api* /upload* /_upload*
    }

    reverse_proxy @backend 127.0.0.1:8000
}
EOF

echo "[start.sh] Caddyfile created"

############################################
# 2. Start Reflex backend ONLY
############################################

echo "[start.sh] Starting Reflex backend..."

reflex run \
  --env prod \
  --backend-host 0.0.0.0 \
  --backend-port 8000 \
  >/tmp/reflex.log 2>&1 &

############################################
# 3. Download Caddy if not present
############################################

if [ ! -f ./caddy ]; then
    echo "[start.sh] Downloading Caddy..."

    curl -L \
      https://github.com/caddyserver/caddy/releases/latest/download/caddy_linux_amd64.tar.gz \
      -o caddy.tar.gz

    tar -xzf caddy.tar.gz
    chmod +x caddy
fi

############################################
# 4. Start Caddy (public server)
############################################

echo "[start.sh] Starting Caddy..."

exec ./caddy run --config Caddyfile --adapter caddyfile
