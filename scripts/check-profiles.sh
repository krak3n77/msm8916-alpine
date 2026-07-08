#!/bin/bash
# ponytail: profile contract smoke check — runs on host, no VM needed
set -euo pipefail

PROFILES_DIR="$(cd "$(dirname "$0")/../profiles" && pwd)"
FAIL=0

# Source default + optional named profile, then assert key=expected pairs
check_profile() {
    local name="$1"; shift
    # Reset all contract vars so stale state doesn't mask missing keys
    unset USB_GADGET_INSTALL USB_GADGET_ENABLED USB_GADGET_OTG \
          OCTOPRINT_PREINSTALL ZORAXY_PREINSTALL DOCKER_ENABLE \
          PROFILE_PACKAGES PROFILE_SERVICES 2>/dev/null || true
    # Load order: base defaults → named profile
    # shellcheck source=/dev/null
    source "$PROFILES_DIR/default.env"
    if [ "$name" != "default" ]; then
        # shellcheck source=/dev/null
        source "$PROFILES_DIR/${name}.env"
    fi

    local ok=1
    for kv in "$@"; do
        local key="${kv%%=*}" expected="${kv#*=}"
        local actual
        actual="$(eval echo "\${${key}:-}")"
        if [ "$actual" != "$expected" ]; then
            echo "  FAIL [$name] $key: expected '$expected', got '$actual'"
            ok=0; FAIL=1
        fi
    done
    [ "$ok" = 1 ] && echo "  OK   [$name]"
}

echo "[*] Checking profile contract..."

check_profile default \
    USB_GADGET_INSTALL=yes \
    USB_GADGET_ENABLED=yes \
    USB_GADGET_OTG=no \
    OCTOPRINT_PREINSTALL=no \
    ZORAXY_PREINSTALL=no \
    DOCKER_ENABLE=no \
    PROFILE_PACKAGES="" \
    PROFILE_SERVICES=""

check_profile octoprint \
    OCTOPRINT_PREINSTALL=yes \
    USB_GADGET_INSTALL=no \
    USB_GADGET_ENABLED=no \
    USB_GADGET_OTG=yes \
    DOCKER_ENABLE=no \
    ZORAXY_PREINSTALL=no

check_profile docker \
    DOCKER_ENABLE=yes \
    OCTOPRINT_PREINSTALL=no \
    ZORAXY_PREINSTALL=no

check_profile zoraxy \
    ZORAXY_PREINSTALL=yes \
    OCTOPRINT_PREINSTALL=no \
    DOCKER_ENABLE=no

# --- OctoPrint install-path wiring check ---
echo "[*] Checking OctoPrint install path wiring..."
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WIRE_OK=1

# stacks/install-octoprint.sh must exist and be executable
if [ -x "$ROOT_DIR/stacks/install-octoprint.sh" ]; then
    echo "  OK   stacks/install-octoprint.sh exists and is executable"
else
    echo "  FAIL stacks/install-octoprint.sh missing or not executable"
    WIRE_OK=0; FAIL=1
fi

# build-rootfs.sh must reference install-octoprint.sh inside OCTOPRINT_PREINSTALL guard
BUILD_ROOTFS="$ROOT_DIR/scripts/build-rootfs.sh"
if grep -q 'OCTOPRINT_PREINSTALL.*yes' "$BUILD_ROOTFS" && \
   grep -q 'install-octoprint.sh' "$BUILD_ROOTFS"; then
    echo "  OK   build-rootfs.sh wires OCTOPRINT_PREINSTALL → install-octoprint.sh"
else
    echo "  FAIL build-rootfs.sh missing OCTOPRINT_PREINSTALL guard or install-octoprint.sh reference"
    WIRE_OK=0; FAIL=1
fi

# All 5 USB serial modules must be referenced in build-rootfs.sh
for _mod in cdc-acm ch341 ftdi_sio pl2303 usbserial; do
    if grep -q "${_mod}" "$BUILD_ROOTFS"; then
        echo "  OK   ${_mod} referenced in build-rootfs.sh"
    else
        echo "  FAIL ${_mod} not referenced in build-rootfs.sh"
        WIRE_OK=0; FAIL=1
    fi
done

[ "$WIRE_OK" = 1 ] && echo "  OK   [octoprint-install-path]"

if [ "$FAIL" = 0 ]; then
    echo "[+] All profile checks passed"
else
    echo "[!] Profile check failed"
    exit 1
fi
