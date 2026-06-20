#!/bin/bash
set -euo pipefail

OCTOPRINT_USER="octoprint"
INSTALL_DIR="/opt/octoprint"
VENV_DIR="$INSTALL_DIR/venv"
DATA_DIR="/var/lib/octoprint"
VERSION_FILE="$INSTALL_DIR/version"
YES=0

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) YES=1 ;;
        *) echo "ERROR: unknown argument: $1"; exit 1 ;;
    esac
    shift
done

log() { echo "$@"; }
run_quiet() { "$@"; }

# Must run as root
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root"; exit 1; }

log "[*] Installing system dependencies..."
run_quiet apk add --no-cache --no-interactive python3 python3-dev py3-netifaces gcc musl-dev libffi-dev openssl-dev linux-headers

# Create dedicated non-root service user/group if not present
if ! getent group "$OCTOPRINT_USER" >/dev/null; then
    run_quiet addgroup -S "$OCTOPRINT_USER"
fi
if ! id "$OCTOPRINT_USER" &>/dev/null; then
    log "[*] Creating user '$OCTOPRINT_USER'..."
    run_quiet adduser -S -D -H -G "$OCTOPRINT_USER" -h "$DATA_DIR" -s /sbin/nologin "$OCTOPRINT_USER"
fi
# ponytail: addgroup is idempotent on Alpine (no-op if already a member)
if run_quiet addgroup "$OCTOPRINT_USER" dialout; then
    log "[*] '$OCTOPRINT_USER' is in the 'dialout' group (serial device access)."
else
    echo "[!] WARNING: could not add '$OCTOPRINT_USER' to 'dialout' group."
fi

log "[*] Fetching latest OctoPrint release..."
LATEST=$(wget -qO- https://pypi.org/pypi/OctoPrint/json \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['info']['version'])")
log "[*] Latest version: $LATEST"

# Check current installed version (idempotency guard)
CURRENT=""
[ -f "$VERSION_FILE" ] && CURRENT=$(cat "$VERSION_FILE")

if [ "$CURRENT" = "$LATEST" ] && [ -x "$VENV_DIR/bin/octoprint" ] && [ -f "/etc/init.d/octoprint" ]; then
    log "[+] OctoPrint $LATEST is already up to date, nothing to do."
    exit 0
fi

[ -n "$CURRENT" ] && log "[*] Updating $CURRENT -> $LATEST..." || log "[*] Installing OctoPrint $LATEST..."

# Create install dir; preserve DATA_DIR if it already exists (user config/uploads)
mkdir -p "$INSTALL_DIR"
if [ ! -d "$DATA_DIR" ]; then
    mkdir -p "$DATA_DIR"
fi

log "[*] Setting up Python virtual environment..."
run_quiet python3 -m venv --system-site-packages "$VENV_DIR"

log "[*] Installing OctoPrint into venv (may take several minutes on this device)..."
run_quiet "$VENV_DIR/bin/pip" install --quiet --upgrade pip
run_quiet "$VENV_DIR/bin/pip" install --quiet "OctoPrint==$LATEST"

echo "$LATEST" > "$VERSION_FILE"
chown -R "$OCTOPRINT_USER:$OCTOPRINT_USER" "$INSTALL_DIR" "$DATA_DIR"

log "[*] Installing OpenRC service..."
cat > /etc/init.d/octoprint <<'EOF'
#!/sbin/openrc-run
# OpenRC service for OctoPrint

name="octoprint"
description="OctoPrint 3D printer web interface"

OCTOPRINT_USER="octoprint"
VENV_DIR="/opt/octoprint/venv"
DATA_DIR="/var/lib/octoprint"

command="$VENV_DIR/bin/octoprint"
command_args="serve --host 0.0.0.0 --port 5000 --basedir $DATA_DIR"
command_user="$OCTOPRINT_USER"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"
output_log="/var/log/octoprint/octoprint.log"
error_log="/var/log/octoprint/octoprint.log"

depend() {
    need net
    after localmount
}

start_pre() {
    if [ ! -x "$command" ]; then
        eerror "OctoPrint not found at $command — run install-octoprint.sh first"
        return 1
    fi
    mkdir -p /var/log/octoprint
    chown "$OCTOPRINT_USER" /var/log/octoprint
}
EOF
chmod 755 /etc/init.d/octoprint
run_quiet rc-update add octoprint default

# ponytail: minimal sanity check - binary must be callable
"$VENV_DIR/bin/octoprint" --version >/dev/null \
    && log "[+] Installation verified." \
    || { echo "[!] WARNING: octoprint binary check failed."; exit 1; }

log "[+] Done! OctoPrint $LATEST installed."
log "    Install : $INSTALL_DIR"
log "    Venv    : $VENV_DIR"
log "    Data    : $DATA_DIR"
log "    Binary  : $VENV_DIR/bin/octoprint"
log ""
log "    Service : /etc/init.d/octoprint (enabled in default runlevel)"
log ""
log "[*] Start now with: rc-service octoprint start"
