"""
OctoPrint-LedStatus: visual LED feedback for printer states.

Calls /usr/local/sbin/led-helper via sudo to control:
  green:wan  — on=idle/ready, off=disconnected/error
  blue:wlan  — off=idle/ready, fast-blink=disconnected/error

red:power is never touched.
"""
import subprocess

import octoprint.plugin
import octoprint.events as events

HELPER = "/usr/local/sbin/led-helper"


# Module-level so smoke_check.py can test degrade behaviour without OctoPrint.
def _set_led_state(state):
    """Invoke helper. Silently degrades if helper/sudo/LEDs are missing."""
    try:
        subprocess.run(
            ["sudo", HELPER, state],
            capture_output=True,
            timeout=5,
        )
    except Exception:  # noqa: BLE001  # ponytail: broad catch — OctoPrint must not crash
        pass


class LedStatusPlugin(
    octoprint.plugin.StartupPlugin,
    octoprint.plugin.EventHandlerPlugin,
):
    def on_after_startup(self):
        # Safe default: assume disconnected until we hear otherwise.
        _set_led_state("disconnected")

    def on_event(self, event, payload):
        if event == events.Events.CONNECTED:
            _set_led_state("idle")
        elif event in (events.Events.DISCONNECTED, events.Events.ERROR):
            _set_led_state("disconnected")


__plugin_name__ = "LED Status"
__plugin_version__ = "1.0.0"
__plugin_description__ = "Visual LED feedback for printer ready/error states"
__plugin_pythoncompat__ = ">=3.7,<4"
__plugin_implementation__ = LedStatusPlugin()
