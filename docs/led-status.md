# LED Status — MSM8916 OctoPrint Appliance

The LED Status plugin (v1.0.0) drives the dongle's two coloured LEDs to show
OctoPrint printer state at a glance. It is preinstalled by `install-octoprint.sh`.

## Hardware contract

The MSM8916 dongle exposes three LEDs under `/sys/class/leds/`:

| sysfs path | Colour | Managed |
|---|---|---|
| `green:wan` | Green | ✓ — plugin controls brightness |
| `blue:wlan` | Blue | ✓ — plugin controls brightness / blink |
| `red:power` | Red | ✗ — device default; **intentionally not managed** |

The red power LED is driven by the hardware or kernel default and is left
untouched. The plugin never writes to `/sys/class/leds/red:power`.

## LED state mapping

| OctoPrint state | Helper arg | Green (`green:wan`) | Blue (`blue:wlan`) |
|---|---|---|---|
| Startup / booting | `disconnected` | off | fast-blink (100 ms) |
| Printer connected, idle | `idle` | solid on | off |
| Printing | `printing` | solid on | solid on |
| Paused | `paused` | solid on | slow-blink (500 ms) |
| Error / print failed | `disconnected` | off | fast-blink (100 ms) |
| Printer disconnected | `disconnected` | off | fast-blink (100 ms) |
| Shutdown / plugin stop | `off` | off | off |

> **Summary:** Green = OctoPrint is connected to the printer. Blue = active
> job or error activity. Both off = shutdown or LED system unavailable.

## Components

| Component | Location on device | Source |
|---|---|---|
| Plugin zip | `/opt/octoprint/venv/lib/…/OctoPrint_LedStatus-1.0.0.dist-info` | `plugins/octoprint-led-status/dist/OctoPrint-LedStatus-1.0.0.zip` |
| Helper script | `/usr/local/sbin/led-helper` (root:root 0755) | `plugins/octoprint-led-status/helper/led-helper` |
| Sudoers rule | `/etc/sudoers.d/octoprint-led` (root:root 0440) | `plugins/octoprint-led-status/sudoers/octoprint-led` |

The sudoers rule is narrowly scoped — it allows `octoprint` to run
`/usr/local/sbin/led-helper` with only the six explicit state arguments
(`idle`, `disconnected`, `printing`, `paused`, `error`, `off`). No wildcard.

## Live-device install / test

Run on the appliance after `install-octoprint.sh` has completed (the installer
handles all of this automatically; the steps below are for manual updates or
re-installs):

```bash
# 1. Copy plugin zip and helper to the device (from build host)
scp plugins/octoprint-led-status/dist/OctoPrint-LedStatus-1.0.0.zip  root@<device>:/tmp/
scp plugins/octoprint-led-status/helper/led-helper                    root@<device>:/tmp/
scp plugins/octoprint-led-status/sudoers/octoprint-led                root@<device>:/tmp/

# 2. On the device: install plugin into the venv
sudo /opt/octoprint/venv/bin/pip install /tmp/OctoPrint-LedStatus-1.0.0.zip

# 3. Deploy helper and sudoers rule
sudo install -o root -g root -m 0755 /tmp/led-helper    /usr/local/sbin/led-helper
sudo install -o root -g root -m 0440 /tmp/octoprint-led /etc/sudoers.d/octoprint-led

# 4. Validate sudoers
sudo visudo -c

# 5. Restart OctoPrint
sudo rc-service octoprint restart

# 6. Smoke-test the helper directly (as the octoprint user)
sudo -u octoprint sudo /usr/local/sbin/led-helper idle
sudo -u octoprint sudo /usr/local/sbin/led-helper printing
sudo -u octoprint sudo /usr/local/sbin/led-helper disconnected
# Watch the dongle LEDs change; restore to idle when done
sudo -u octoprint sudo /usr/local/sbin/led-helper idle
```

Confirm the plugin loaded in OctoPrint:

```bash
/opt/octoprint/venv/bin/pip show OctoPrint-LedStatus
# expect: Version: 1.0.0
```

### Plugin removal and reinstall

The installer is idempotent. Re-running `sudo ~/install-octoprint.sh` will:

- Skip pip install if version `1.0.0` is already present.
- Always overwrite `/usr/local/sbin/led-helper` (root-owned; safe to clobber).
- Always overwrite `/etc/sudoers.d/octoprint-led`.

To force a clean reinstall of the plugin only:

```bash
sudo /opt/octoprint/venv/bin/pip uninstall -y OctoPrint-LedStatus
sudo /opt/octoprint/venv/bin/pip install /tmp/OctoPrint-LedStatus-1.0.0.zip
sudo rc-service octoprint restart
```

## Troubleshooting

| Symptom | Check |
|---|---|
| LEDs not reacting to state changes | Confirm sysfs paths exist: `ls /sys/class/leds/`. If `green:wan` or `blue:wlan` are absent the helper silently degrades — OctoPrint still works |
| `sudo: /usr/local/sbin/led-helper: command not found` | Helper not deployed: run step 3 of the live-device install above |
| Permission denied calling helper | Sudoers rule missing or wrong path: `sudo visudo -c`, check `/etc/sudoers.d/octoprint-led` |
| Plugin not listed in OctoPrint Plugin Manager | `pip show OctoPrint-LedStatus` — if absent, reinstall from zip; restart OctoPrint |
| Red LED turns off unexpectedly | Not caused by this plugin — check power/hardware; plugin never writes to `red:power` |
| After reinstall LEDs stay in wrong state | Restart OctoPrint: `sudo rc-service octoprint restart`; plugin sets `disconnected` on startup |
