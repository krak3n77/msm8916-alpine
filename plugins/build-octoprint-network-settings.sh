#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$ROOT/octoprint-network-settings"
VERSION="$(sed -n 's/.*version="\([^"]*\)".*/\1/p' "$PLUGIN_DIR/setup.py" | head -n1)"
OUT_DIR="${1:-$PLUGIN_DIR/dist}"
ZIP="$OUT_DIR/OctoPrint-NetworkSettings-${VERSION}.zip"

[ -n "$VERSION" ] || { echo "ERROR: plugin version not found"; exit 1; }
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

python3 - "$PLUGIN_DIR" "$ZIP" <<'PY'
import os, sys, zipfile
root, zip_path = sys.argv[1:]
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in {"__pycache__", "dist", ".git"}]
        for name in files:
            if name.endswith((".pyc", ".pyo")):
                continue
            path = os.path.join(base, name)
            z.write(path, os.path.relpath(path, root))
PY

echo "$ZIP"
