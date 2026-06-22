"""
OctoPrint-NetworkSettings: WiFi / IPv4 configuration via nm-wrapper.

Backend routes (BlueprintPlugin):
  GET  /api/plugin/network_settings/status   → merged status+read JSON
  POST /api/plugin/network_settings/save     → save-wifi-dhcp or save-wifi-static
  POST /api/plugin/network_settings/apply    → backup-wifi, save, apply-wifi
  POST /api/plugin/network_settings/restore  → restore-wifi
"""
import json
import subprocess

import octoprint.plugin
from flask import jsonify, request

WRAPPER = "/usr/local/sbin/nm-wrapper"


# ── core helpers (module-level for testability) ──────────────────────────────

def _run(args, timeout=10):
    """
    Run nm-wrapper via sudo. Returns (dict, returncode).
    Never raises — all errors become {"error": "..."} with rc=1.
    """
    try:
        result = subprocess.run(
            ["sudo", WRAPPER] + args,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        data = json.loads(result.stdout)
        return data, result.returncode
    except subprocess.TimeoutExpired:
        return {"error": "nm-wrapper timed out"}, 1
    except json.JSONDecodeError as exc:
        return {"error": f"nm-wrapper returned non-JSON: {exc}"}, 1
    except Exception as exc:  # noqa: BLE001
        return {"error": str(exc)}, 1


def _get_network_info():
    """
    Merge status + read into one dict.
    Status drives connectivity; read failures are returned as config_error.
    Returns (dict, ok_bool).
    """
    status, status_rc = _run(["status"])
    if status_rc != 0:
        return status, False

    config, config_rc = _run(["read"])
    merged = {
        "interface": status.get("interface", "wlan0"),
        "state": status.get("state", "unknown"),
        "connection": status.get("connection", ""),
        "ssid": "",
        "ipv4_method": "auto",
        "address": "",
        "gateway": "",
        "dns": "",
    }

    if config_rc == 0:
        merged.update({
            "ssid": config.get("ssid", "") or merged["connection"],
            "ipv4_method": config.get("ipv4_method", "auto"),
            "address": config.get("address", ""),
            "gateway": config.get("gateway", ""),
            "dns": config.get("dns", ""),
        })
    else:
        merged["ssid"] = merged["connection"]
        merged["config_error"] = config.get("error", "failed to read config")

    return merged, True


def _save_settings(body):
    """
    Dispatch to save-wifi-dhcp or save-wifi-static based on body["mode"].
    Returns (dict, returncode).
    """
    ssid = str(body.get("ssid", "")).strip()
    password = str(body.get("password", "")).strip()
    mode = str(body.get("mode", "auto")).strip() or "auto"

    if mode not in ("auto", "manual"):
        return {"error": "mode must be auto or manual"}, 1

    if mode == "manual":
        args = [
            "save-wifi-static",
            ssid,
            password,
            str(body.get("address", "")).strip(),
            str(body.get("gateway", "")).strip(),
            str(body.get("dns", "")).strip(),
        ]
    else:
        args = ["save-wifi-dhcp", ssid, password]

    return _run(args)


def _apply_settings(body):
    """
    Backup current config, save requested settings, then reconnect WiFi.
    Returns (dict, returncode).
    """
    backup, backup_rc = _run(["backup-wifi"])
    if backup_rc != 0:
        return backup, backup_rc

    saved, save_rc = _save_settings(body)
    if save_rc != 0:
        return saved, save_rc

    applied, apply_rc = _run(["apply-wifi"], timeout=30)
    if apply_rc != 0:
        return applied, apply_rc

    return {
        "ok": True,
        "backup": backup.get("backup", ""),
        "ssid": saved.get("ssid", ""),
        "ipv4_method": saved.get("ipv4_method", ""),
        "interface": applied.get("interface", "wlan0"),
        "connection": applied.get("connection", ""),
    }, 0


def _restore_settings():
    """
    Restore the most recent backup and reconnect WiFi.
    Returns (dict, returncode).
    """
    return _run(["restore-wifi"], timeout=30)


# ── OctoPrint plugin class ───────────────────────────────────────────────────

class NetworkSettingsPlugin(
    octoprint.plugin.SettingsPlugin,
    octoprint.plugin.TemplatePlugin,
    octoprint.plugin.AssetPlugin,
    octoprint.plugin.BlueprintPlugin,
):

    @octoprint.plugin.BlueprintPlugin.route("/status", methods=["GET"])
    def api_status(self):
        data, ok = _get_network_info()
        return jsonify(data), (200 if ok else 500)

    @octoprint.plugin.BlueprintPlugin.route("/save", methods=["POST"])
    def api_save(self):
        body = request.get_json(silent=True) or {}
        data, rc = _save_settings(body)
        return jsonify(data), (200 if rc == 0 else 400)

    @octoprint.plugin.BlueprintPlugin.route("/apply", methods=["POST"])
    def api_apply(self):
        body = request.get_json(silent=True) or {}
        data, rc = _apply_settings(body)
        return jsonify(data), (200 if rc == 0 else 500)

    @octoprint.plugin.BlueprintPlugin.route("/restore", methods=["POST"])
    def api_restore(self):
        data, rc = _restore_settings()
        return jsonify(data), (200 if rc == 0 else 500)

    def get_template_configs(self):
        return [{"type": "settings", "name": "Network Settings", "custom_bindings": True}]

    def get_assets(self):
        return {"js": ["js/network_settings.js"]}

    def get_settings_defaults(self):
        return {}


# ── plugin registration ──────────────────────────────────────────────────────

__plugin_name__ = "Network Settings"
__plugin_version__ = "1.0.0"
__plugin_description__ = "WiFi / IP configuration via NetworkManager"
__plugin_pythoncompat__ = ">=3.7,<4"
__plugin_implementation__ = NetworkSettingsPlugin()
