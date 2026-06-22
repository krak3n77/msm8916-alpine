#!/bin/bash
# install-nm-wrapper.sh: install the privileged NM status/read wrapper for OctoPrint.
# Must run as root. Idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPER_SRC="${WRAPPER_SRC:-$SCRIPT_DIR/../configs/nm-wrapper/nm-wrapper}"
WRAPPER_DST="/usr/local/sbin/nm-wrapper"
SUDOERS_FILE="/etc/sudoers.d/octoprint-nm"
OCTOPRINT_USER="octoprint"

log() { echo "$@"; }

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root"; exit 1; }
[ -f "$WRAPPER_SRC" ]  || { echo "ERROR: wrapper source not found: $WRAPPER_SRC"; exit 1; }

log "[*] Installing nm-wrapper to $WRAPPER_DST ..."
install -Dm0755 -o root -g root "$WRAPPER_SRC" "$WRAPPER_DST"
log "[+] Installed $WRAPPER_DST"

# Restrict octoprint user to exactly the two read-only wrapper subcommands.
# ponytail: separate sudoers file so install-octoprint.sh and install-nm-wrapper.sh
#           are independent and idempotent when rerun in either order.
log "[*] Writing sudoers entry $SUDOERS_FILE ..."
cat > "$SUDOERS_FILE" <<SUDOERS
# OctoPrint network plugin: NM wrapper access (read + DHCP/static config write + apply + backup/restore).
$OCTOPRINT_USER ALL=(root) NOPASSWD: $WRAPPER_DST status, $WRAPPER_DST read, $WRAPPER_DST save-wifi-dhcp, $WRAPPER_DST save-wifi-static, $WRAPPER_DST apply-wifi, $WRAPPER_DST backup-wifi, $WRAPPER_DST restore-wifi
SUDOERS
chown root:root "$SUDOERS_FILE"
chmod 0440 "$SUDOERS_FILE"
log "[+] Wrote $SUDOERS_FILE"

log "[*] Verifying sudoers syntax ..."
visudo -c -f "$SUDOERS_FILE" && log "[+] Sudoers OK" || { echo "ERROR: sudoers syntax check failed"; exit 1; }

log "[+] nm-wrapper install complete."
log "    Test: sudo $WRAPPER_DST status"
log "    Self-check: bash $SCRIPT_DIR/../configs/nm-wrapper/nm-wrapper.check $WRAPPER_DST"
