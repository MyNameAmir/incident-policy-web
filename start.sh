#!/usr/bin/env bash
set -euo pipefail

# Generate the web folder(s)
reflex init

# Patch ANY generated vite config under any ".web" folder
python - <<'PY'
from pathlib import Path
import re

targets = list(Path(".").rglob(".web/vite.config.*"))
print(f"[patch] Found {len(targets)} vite config(s):")
for p in targets:
    print(" -", p)

if not targets:
    raise SystemExit("[patch] No vite.config found under any .web folder")

for p in targets:
    s = p.read_text(encoding="utf-8")

    # If already patched, skip
    if "allowedHosts" in s:
        print(f"[patch] already has allowedHosts: {p}")
        continue

    new = s

    # Insert allowedHosts into `server: { ... }`
    new, n1 = re.subn(r"(server\s*:\s*\{\s*)", r"\1\n    allowedHosts: true,\n", new, count=1)

    # Fallback insert into `server = { ... }`
    if n1 == 0:
        new, n2 = re.subn(r"(server\s*=\s*\{\s*)", r"\1\n    allowedHosts: true,\n", new, count=1)
    else:
        n2 = 0

    if n1 == 0 and n2 == 0:
        raise SystemExit(f"[patch] Could not find server block to patch in {p}")

    p.write_text(new, encoding="utf-8")
    print(f"[patch] Patched {p}")
PY

# Start Reflex
exec reflex run
