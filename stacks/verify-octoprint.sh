#!/bin/bash
# OctoPrint appliance verification.
# Automated checks run immediately.
# Manual device-side checks are printed as a numbered checklist.
set -euo pipefail

PASS=0
FAIL=0

ok()   { echo "[PASS] $*"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $*"; FAIL=$((FAIL+1)); }

# Resolve repo root relative to this script so it can be called from anywhere.
REPO="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== OctoPrint Verification ==="
echo ""

# ---- 1. Syntax checks ----------------------------------------
echo "-- 1. Syntax checks --"

for script in stacks/install-octoprint.sh; do
    if bash -n "$REPO/$script" 2>&1; then
        ok "bash -n $script"
    else
        fail "bash -n $script"
    fi
done

# Extract and syntax-check the inline OpenRC init script embedded in the installer.
TMPINIT=$(mktemp)
awk '/^cat > \/etc\/init.d\/octoprint <<.EOF./{p=1;next} /^EOF$/{p=0} p' \
    "$REPO/stacks/install-octoprint.sh" > "$TMPINIT"
if bash -n "$TMPINIT" 2>/dev/null; then
    ok "OpenRC init script (embedded in installer) is valid sh syntax"
else
    fail "OpenRC init script (embedded in installer) has syntax errors"
fi
rm -f "$TMPINIT"

# ---- 2. USB gadget policy ------------------------------------
echo ""
echo "-- 2. USB gadget policy --"

if grep -q 'USB_GADGET_INSTALL="no"' "$REPO/profiles/octoprint.env"; then
    ok "OctoPrint profile does not install usb-gadget tooling"
else
    fail "OctoPrint profile should set USB_GADGET_INSTALL=\"no\""
fi

if grep -q 'if \[ "$USB_GADGET_INSTALL" = "yes" \]' "$REPO/scripts/generate_alpine_rootfs.sh"; then
    ok "Rootfs generator gates usb-gadget install on USB_GADGET_INSTALL"
else
    fail "Rootfs generator installs usb-gadget unconditionally"
fi

# ---- 3. Idempotency guard ------------------------------------
echo ""
echo "-- 3. Idempotency guard --"

if grep -q 'already up to date, nothing to do' "$REPO/stacks/install-octoprint.sh"; then
    ok "Installer skips reinstall when installed version matches latest"
else
    fail "Installer missing version idempotency guard"
fi

if grep -q 'if \[ ! -d.*DATA_DIR' "$REPO/stacks/install-octoprint.sh"; then
    ok "Installer preserves DATA_DIR on rerun (no data wipe)"
else
    fail "Installer does not preserve DATA_DIR on rerun"
fi

# ---- 4. OctoPrint no-LTE DTB profile -------------------------
echo ""
echo "-- 4. OctoPrint no-LTE DTB profile --"
DTS="$REPO/dts/msm8916-yiming-uz801v3-octoprint.dts"

if [ -f "$DTS" ]; then
    ok "OctoPrint DTB profile exists: dts/msm8916-yiming-uz801v3-octoprint.dts"

    # Each node block is &foo {\n\tstatus = "disabled";\n}; — grep -A2 is sufficient.
    for node in mpss mpss_mem mba_mem bam_dmux bam_dmux_dma venus venus_mem; do
        if grep -A2 "^&${node} {" "$DTS" | grep -q 'status = "disabled"'; then
            ok "  &${node} is disabled"
        else
            fail "  &${node} is NOT disabled in OctoPrint profile"
        fi
    done

    # WiFi (wcnss) must NOT be overridden/disabled — it inherits enabled from base DTS.
    if grep -A2 '&wcnss' "$DTS" | grep -q 'disabled'; then
        fail "  WiFi (&wcnss) is disabled — it must stay enabled"
    else
        ok "  WiFi (&wcnss) not overridden — stays enabled from base DTS"
    fi
else
    fail "OctoPrint DTB profile not found: dts/msm8916-yiming-uz801v3-octoprint.dts"
fi

# ---- 5. USB serial module artifacts (issue-005) --------------
echo ""
echo "-- 5. USB serial module artifacts --"
_KERNEL_VER="6.12.1-msm8916"
_ARTIFACT_DIR="$REPO/modules/octoprint-usb-serial/${_KERNEL_VER}"
for _mod in ch341.ko usbserial.ko cdc-acm.ko; do
    if [ -f "$_ARTIFACT_DIR/$_mod" ]; then
        ok "USB module artifact present: ${_mod}"
    else
        fail "USB module artifact missing: ${_mod} in modules/octoprint-usb-serial/${_KERNEL_VER}"
    fi
done
unset _KERNEL_VER _ARTIFACT_DIR _mod

if grep -q 'octoprint-usb.start' "$REPO/scripts/generate_alpine_rootfs.sh" \
    && grep -q 'echo host > "$ROLE"' "$REPO/scripts/generate_alpine_rootfs.sh" \
    && grep -q 'modprobe ch341' "$REPO/scripts/generate_alpine_rootfs.sh" \
    && grep -q 'modprobe cdc_acm' "$REPO/scripts/generate_alpine_rootfs.sh"; then
    ok "OctoPrint image forces USB host mode and preloads serial modules at boot"
else
    fail "OctoPrint image missing USB host/module boot setup"
fi

# ---- Summary --------------------------------------------------
echo ""
echo "=== Automated: $PASS passed, $FAIL failed ==="
echo ""

# ---- Manual device-side checklist ----------------------------
cat <<'MANUAL'
=== Manual checks (run on the device) ===

1. OpenRC service lifecycle:
     rc-service octoprint start   && rc-service octoprint status   # expect: started
     rc-service octoprint restart && rc-service octoprint status   # expect: started
     rc-service octoprint stop    && rc-service octoprint status   # expect: stopped
     rc-service octoprint start

2. Installer reruns safely (no data wipe):
     # While OctoPrint is installed, run the installer again:
     sudo bash ~/install-octoprint.sh
     # Expect: "already up to date, nothing to do." — no reinstall, no removal of /var/lib/octoprint

3. Memory — compare free RAM before and after the OctoPrint DTB:
     # Boot with generic DTB (msm8916-yiming-uz801v3.dtb) and note:
     free -m
     # Reboot with OctoPrint DTB (msm8916-yiming-uz801v3-octoprint.dtb) and compare:
     free -m
     # Expect: ~30–60 MB more free RAM (modem + Venus firmware memory reclaimed)

4. WiFi still works after switching to the OctoPrint DTB:
     ip link show wlan0             # interface must be present
     ping -c 3 8.8.8.8              # or any reachable LAN host

5. LTE modem absent in OctoPrint profile:
     ls /sys/bus/platform/devices/ | grep -E 'mpss|venus|bam_dmux'
     # expect: no output (modem remoteproc not registered)
     ip link | grep -E 'wwan|rmnet'
     # expect: no output

6. Printer serial device detection (USB OTG cable + printer connected):
     ls /dev/ttyUSB* /dev/ttyACM*   # expect at least one device
     groups octoprint | grep -w dialout   # expect: dialout present

7. OctoPrint reachability on port 5000 (from another LAN host):
     curl -sf http://<device-ip>:5000/   # expect HTTP 200 with OctoPrint HTML
     # Or open in a browser: http://<device-ip>:5000/

MANUAL

[ "$FAIL" -eq 0 ] || { echo "Some automated checks failed — review above."; exit 1; }
exit 0
