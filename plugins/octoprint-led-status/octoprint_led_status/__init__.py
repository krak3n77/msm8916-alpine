"""
OctoPrint-LedStatus: visual LED feedback for printer states.

Calls /usr/local/sbin/led-helper via sudo to control:
  red:power  — on=any active state (idle/printing/paused/disconnected/error), off=shutdown
  green:wan  — on=idle/ready/printing/paused, off=disconnected/error/off
  blue:wlan  — off=idle, on=printing, slow-blink=paused, fast-blink=disconnected/error
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
    octoprint.plugin.ShutdownPlugin,
    octoprint.plugin.EventHandlerPlugin,
    octoprint.plugin.TemplatePlugin,
):
    def on_after_startup(self):
        # Safe default: assume disconnected until we hear otherwise.
        _set_led_state("disconnected")

    def on_shutdown(self):
        _set_led_state("off")

    def get_template_configs(self):
        return [{"type": "settings", "name": "LED Status", "template": "led_status_settings.jinja2"}]

    def on_event(self, event, payload):
        e = events.Events
        if event == e.CONNECTED:
            _set_led_state("idle")
        elif event in (e.DISCONNECTED, e.ERROR):
            _set_led_state("disconnected")
        elif event in (e.PRINT_STARTED, e.PRINT_RESUMED):
            _set_led_state("printing")
        elif event == e.PRINT_PAUSED:
            _set_led_state("paused")
        elif event in (e.PRINT_DONE, e.PRINT_CANCELLED):
            _set_led_state("idle")
        elif event == e.PRINT_FAILED:
            _set_led_state("disconnected")


__plugin_name__ = "LED Status"
__plugin_version__ = "1.0.0"
__plugin_description__ = "Visual LED feedback for printer ready/error states"
__plugin_pythoncompat__ = ">=3.7,<4"
__plugin_implementation__ = LedStatusPlugin()
