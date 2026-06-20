# OctoPrint on MSM8916 Alpine

OctoPrint core for a Creality Ender-3 V3 SE (or similar USB-serial printer) running on an MSM8916
dongle with constrained memory (~384 MB usable). Read this before installing.

## What this is (and isn't)

| | This setup |
|---|---|
| OctoPrint core | ✓ |
| OctoPi image | ✗ — this is Alpine Linux, not OctoPi |
| Docker | ✗ — intentionally avoided; too heavy for ~384 MB RAM |
| Webcam / MJPEG streaming | ✗ — out of scope for v1 |
| Pre-installed plugins | ✗ — OctoPrint core only |
| LTE modem | ✗ — disabled in the OctoPrint DTB profile to reclaim ~86 MB RAM |

OctoPrint runs as a native OpenRC service under a dedicated `octoprint` user, installed via
`install-octoprint.sh` into `/opt/octoprint/venv`.

## Memory layout

The dongle has 512 MB total RAM. With the generic DTB, modem firmware and video decode reserves
consume roughly 91 MB. The OctoPrint DTB profile (`msm8916-yiming-uz801v3-octoprint.dtb`) disables
those regions and leaves ~384 MB usable for the OS and OctoPrint.

On top of that, the image configures a **256 MB zram swap** device using lz4 compression
(`/etc/local.d/zram.start`). zram compresses idle pages in RAM; it is not a substitute for real
RAM but it gives OctoPrint headroom when the kernel needs to reclaim pages. No external swap
device is required.

**Keep plugins light.** Each installed OctoPrint plugin consumes RAM at startup. Avoid heavy
plugins (OctoPrint-Dashboard, timelapse, etc.) on this device.

## USB and WiFi — read this first

The printer connects over **USB OTG host mode**. The same USB port is used for USB gadget
networking (the NCM/RNDIS interface that gives you a wired SSH session). These two modes are
mutually exclusive.

> **Set up WiFi before switching to USB host mode.** Once the port is in OTG/host mode, USB
> gadget networking is gone. If WiFi is not working you will lose all network access to the
> dongle.

### Switching to USB host mode

```bash
# Confirm WiFi is up first
ip addr show wlan0

# Then switch USB port to OTG host mode
usb-gadget enable_otg
rc-service usb-gadget restart
```

Plug in the printer with a USB-A to USB-C/B cable (or USB OTG adapter). The printer should
enumerate within a few seconds.

## Expected serial devices

When a Creality Ender-3 V3 SE (or similar) is connected via USB, the kernel registers a serial
device. Look for:

| Device | Driver | Typical printer |
|---|---|---|
| `/dev/ttyUSB0` | USB serial (CH340, CP2102) | Creality boards with CH340 chip |
| `/dev/ttyACM0` | CDC-ACM | Printers with STM32 or similar |

```bash
# Check what appeared after connecting the printer
dmesg | tail -20
ls /dev/tty{USB,ACM}* 2>/dev/null
```

The `octoprint` service user is added to the `dialout` group by `install-octoprint.sh` so it can
open serial ports without root.

## DTB profile selection

Set `DTB_FILE` in `variables.env` before building, or update `extlinux.conf` on the device after
first boot:

```bash
# For OctoPrint (LTE + video decode disabled, WiFi kept)
DTB_FILE="msm8916-yiming-uz801v3-octoprint.dtb"

# Generic (LTE enabled)
DTB_FILE="msm8916-yiming-uz801v3.dtb"
```

To switch on a running device:

```bash
# Edit extlinux.conf and reboot
sudo vi /boot/extlinux/extlinux.conf   # change the FDT line
sudo reboot
```

Confirm after reboot:

```bash
# LTE modem devices should be absent in the OctoPrint profile
ls /dev/cdc-wdm* 2>/dev/null || echo "modem absent (expected)"
free -m   # should show ~384 MB total
```

## Install

Run after first boot, once WiFi is working and the OctoPrint DTB profile is active:

```bash
sudo ~/install-octoprint.sh
```

The script is idempotent — safe to rerun if interrupted. It:

1. Installs Alpine system dependencies (`python3`, build headers)
2. Creates the `octoprint` service user
3. Fetches the latest OctoPrint release from PyPI into `/opt/octoprint/venv`
4. Installs the OpenRC service and enables it in the default runlevel

Install takes **10–20 minutes** on the dongle (slow single-core pip build).

## Access

OctoPrint binds to all interfaces on **port 5000**.

```bash
# From your laptop — use the dongle's WiFi IP
http://192.168.1.XXX:5000

# Find the WiFi IP
ssh user@192.168.42.1   # USB gadget (only works before OTG switch)
ip addr show wlan0
```

First launch triggers the OctoPrint setup wizard in the browser.

## Service management

```bash
# Start / stop / restart
rc-service octoprint start
rc-service octoprint stop
rc-service octoprint restart

# Status
rc-service octoprint status

# Logs
tail -f /var/log/octoprint/octoprint.log
```

## Disable / uninstall

```bash
# Disable autostart (keeps data intact)
rc-update del octoprint default
rc-service octoprint stop

# Full removal (destroys config and uploaded files)
rc-service octoprint stop
rc-update del octoprint default
rm -rf /opt/octoprint /var/lib/octoprint /var/log/octoprint /etc/init.d/octoprint
deluser octoprint
```

## Troubleshooting

| Symptom | Check |
|---|---|
| No `/dev/ttyUSB0` or `/dev/ttyACM0` | `dmesg | tail -20` — cable, OTG mode, printer power |
| USB gadget lost after OTG switch | Expected — connect via WiFi instead |
| OctoPrint unreachable on port 5000 | `rc-service octoprint status`, check logs |
| OOM / service killed | `free -m`, `dmesg | grep -i oom` — disable heavy plugins, confirm OctoPrint DTB profile |
| Modem still present | Wrong DTB loaded — check `extlinux.conf` FDT line |
| Install fails mid-way | Rerun `sudo ~/install-octoprint.sh` — idempotent |
