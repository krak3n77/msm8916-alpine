# Handoff — OctoPrint USB serial / CH341

## Context

Repo: `/Users/hkfuertes/projects/msm8916-alpine`  
Branch: `octoprint`

Goal: OctoPrint image for MSM8916 dongle with USB gadget removed, USB host mode for printer, and extra USB serial modules (`ch341`, `cdc_acm`, etc.) available for Creality-style printers.

## Current repo state

Committed work already on branch:

- `4606a95` — disable usb-gadget in OctoPrint profile
- `46fe549` — document CH341 kernel module strategy
- `699b86e` — add kernel build env
- `ee57b63` — pin pmaports `v25.06`, drive version from APKBUILD
- `8ba7059` — enable USB serial printer driver config fragment
- `b74a4c2` — build USB serial modules
- `8a24fc5` — install USB serial modules in OctoPrint image

Uncommitted changes still present:

- `Makefile`
  - adds friendly `make modules`
  - keeps `make kernel-modules` as alias
- `scripts/make_modules.sh`
  - one-shot module prep/build script
- `scripts/build-usb-modules.sh`
  - now builds exact `.ko` targets and uses `KBUILD_MODPOST_WARN=1`
- `scripts/generate_alpine_rootfs.sh`
  - copies modules from friendly path
  - creates `/etc/local.d/octoprint-usb.start` for USB host + modprobe at boot
- `stacks/verify-octoprint.sh`
  - checks friendly module dir and boot setup
- `modules/octoprint-usb-serial/6.12.1-msm8916/*.ko`
  - checked-in candidate artifacts to use as-is for OctoPrint builds

Friendly module path:

```text
modules/octoprint-usb-serial/6.12.1-msm8916/
  cdc-acm.ko
  ch341.ko
  ftdi_sio.ko
  pl2303.ko
  usbserial.ko
```

Generated image artifacts currently fetched to host:

```text
files/rootfs.img.gz  Jun 22 00:24
files/boot.img.gz    Jun 22 00:23
files/firmware.zip   Jun 22 00:24
files/gpt_both0.bin  Jun 22 00:24
```

`files/` is ignored.

## Important finding

The earlier flash used stale local `files/rootfs.img.gz` from before the `local.d` boot hook existed. After running `make fetch`, host `files/rootfs.img.gz` was updated from the VM and should contain:

```text
/etc/local.d/octoprint-usb.start
/lib/modules/6.12.1-msm8916/kernel/drivers/usb/serial/{usbserial,ch341,ftdi_sio,pl2303}.ko
/lib/modules/6.12.1-msm8916/kernel/drivers/usb/class/cdc-acm.ko
```

Verified in VM image via `debugfs` before fetch; then fetched to host.

## Last device check

Device: `192.168.77.146` via `sshpass` using `variables.env`.

Before latest fetch/flash, device showed:

```text
modules present: yes
/etc/local.d/octoprint-usb.start: missing
role=device
usb-gadget=absent
usb0=absent
modules loaded: no
```

This means the device had the `.ko`s but not the newest rootfs boot hook.

## Next steps tomorrow

1. Flash the **new fetched** image:

```sh
./flash.sh -l
```

2. Boot device and check:

```sh
. ./variables.env
sshpass -p "$PASSWORD" ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "$USERNAME@192.168.77.146"
```

3. On device, expected:

```sh
ls -l /etc/local.d/octoprint-usb.start
cat /sys/class/usb_role/ci_hdrc.0-role-switch/role   # host
lsmod | grep -E 'ch341|usbserial|cdc_acm'
command -v usb-gadget || echo absent
ip link show usb0 || echo absent
```

4. If role is still `device`, test manually:

```sh
sudo sh -c 'echo host > /sys/class/usb_role/ci_hdrc.0-role-switch/role'
sudo modprobe usbserial
sudo modprobe ch341
sudo modprobe cdc_acm
```

5. Once verified, commit uncommitted changes and module artifacts.

Suggested commit:

```sh
git add Makefile scripts/make_modules.sh scripts/build-usb-modules.sh \
  scripts/generate_alpine_rootfs.sh stacks/verify-octoprint.sh \
  modules/octoprint-usb-serial/6.12.1-msm8916/*.ko HANDOFF.md

git commit -m "feat(octoprint): preload USB host serial modules"
```

## Useful commands

Build modules once in VM:

```sh
make modules
```

Build OctoPrint image in VM:

```sh
make octoprint
```

Fetch image artifacts to host:

```sh
make fetch
```

Verify repo-side OctoPrint checks:

```sh
stacks/verify-octoprint.sh
```

## Skills for next session

- `diagnose` if USB role still boots as `device` or printer does not enumerate.
- `ponytail` remains useful: keep this minimal; avoid full kernel rebuild unless module ABI fails.
- `implement` only if continuing the formal issue workflow and committing/reviewing remaining changes.
