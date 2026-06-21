#!/bin/bash
# Fast validation of the kernel build environment.
# Does NOT download or compile anything — safe to run on the host.
# Exit 0 = all checks pass; Exit 1 = one or more failures.

set -euo pipefail

ERRORS=0

ok()   { echo "[ OK ] $1"; }
fail() { echo "[FAIL] $1"; ERRORS=$((ERRORS + 1)); }
info() { echo "[    ] $1"; }

# --- Tool checks ---
for tool in make wget bc flex bison; do
    command -v "$tool" &>/dev/null && ok "$tool" || fail "$tool not found"
done

# libelf: needed by modules_prepare for BTF / DWARF
if pkg-config --exists libelf 2>/dev/null || find /usr -name 'libelf.h' 2>/dev/null | grep -q .; then
    ok "libelf headers"
else
    fail "libelf-dev not found (apt install libelf-dev)"
fi

# Cross-compiler
if [ "$(uname -m)" = "aarch64" ]; then
    command -v gcc &>/dev/null && ok "gcc (native arm64)" || fail "gcc not found"
else
    command -v aarch64-linux-gnu-gcc &>/dev/null \
        && ok "aarch64-linux-gnu-gcc (cross)" \
        || fail "aarch64-linux-gnu-gcc not found (apt install gcc-aarch64-linux-gnu)"
fi

# --- URL reachability ---
info "Checking upstream URLs (requires network) ..."
wget -q --spider 'https://github.com/msm8916-mainline/linux/archive/v6.12.1-msm8916.tar.gz' 2>/dev/null \
    && ok "kernel source URL reachable (v6.12.1-msm8916)" \
    || fail "kernel source URL not reachable"

wget -q --spider 'https://gitlab.com/postmarketOS/pmaports/-/raw/master/device/community/linux-postmarketos-qcom-msm8916/config-postmarketos-qcom-msm8916.aarch64' 2>/dev/null \
    && ok "pmaports config URL reachable" \
    || fail "pmaports config URL not reachable"

# --- Optional: check if setup was already run ---
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KSRC="$REPO_ROOT/kernel-build/linux-6.12.1-msm8916"
if [ -f "$KSRC/scripts/mod/modpost" ]; then
    ok "modules_prepare already done ($KSRC)"
else
    info "kernel-build not set up yet — run: sudo bash scripts/setup-kernel-build.sh"
fi

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "Environment OK."
    exit 0
else
    echo "$ERRORS check(s) failed."
    exit 1
fi
