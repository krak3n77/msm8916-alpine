#!/bin/bash
set -euo pipefail

OCTOPRINT_USER="octoprint"
INSTALL_DIR="/opt/octoprint"
VENV_DIR="$INSTALL_DIR/venv"
DATA_DIR="/var/lib/octoprint"
VERSION_FILE="$INSTALL_DIR/version"

# Must run as root
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root"; exit 1; }

echo "[*] Installing system dependencies..."
apk add --no-cache python3 python3-dev gcc musl-dev libffi-dev openssl-dev linux-headers

# Create dedicated non-root service user if not present
if ! id "$OCTOPRINT_USER" &>/dev/null; then
    echo "[*] Creating user '$OCTOPRINT_USER'..."
    adduser -S -D -H -h "$DATA_DIR" -s /sbin/nologin "$OCTOPRINT_USER"
fi

echo "[*] Fetching latest OctoPrint release..."
LATEST=$(wget -qO- https://pypi.org/pypi/OctoPrint/json \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['info']['version'])")
echo "[*] Latest version: $LATEST"

# Check current installed version (idempotency guard)
CURRENT=""
[ -f "$VERSION_FILE" ] && CURRENT=$(cat "$VERSION_FILE")

if [ "$CURRENT" = "$LATEST" ] && [ -x "$VENV_DIR/bin/octoprint" ]; then
    echo "[+] OctoPrint $LATEST is already up to date, nothing to do."
    exit 0
fi

[ -n "$CURRENT" ] && echo "[*] Updating $CURRENT -> $LATEST..." || echo "[*] Installing OctoPrint $LATEST..."

# Create install dir; preserve DATA_DIR if it already exists (user config/uploads)
mkdir -p "$INSTALL_DIR"
if [ ! -d "$DATA_DIR" ]; then
    mkdir -p "$DATA_DIR"
fi

echo "[*] Setting up Python virtual environment..."
python3 -m venv "$VENV_DIR"

echo "[*] Installing OctoPrint into venv (may take several minutes on this device)..."
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet "OctoPrint==$LATEST"

echo "$LATEST" > "$VERSION_FILE"
chown -R "$OCTOPRINT_USER:$OCTOPRINT_USER" "$INSTALL_DIR" "$DATA_DIR"

# ponytail: minimal sanity check - binary must be callable
"$VENV_DIR/bin/octoprint" --version >/dev/null \
    && echo "[+] Installation verified." \
    || { echo "[!] WARNING: octoprint binary check failed."; exit 1; }

echo "[+] Done! OctoPrint $LATEST installed."
echo "    Install : $INSTALL_DIR"
echo "    Venv    : $VENV_DIR"
echo "    Data    : $DATA_DIR"
echo "    Binary  : $VENV_DIR/bin/octoprint"
echo ""
echo "[!] Service not yet configured. Set up an OpenRC init script to start OctoPrint"
echo "    as '$OCTOPRINT_USER' with: $VENV_DIR/bin/octoprint serve --host 0.0.0.0 --port 5000 --basedir $DATA_DIR"
