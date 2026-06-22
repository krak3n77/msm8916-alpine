#!/usr/bin/env python3
import os
import sys
import types


ROOT = os.path.dirname(__file__)
sys.path.insert(0, ROOT)


def install_octoprint_stub():
    octoprint = types.ModuleType("octoprint")
    plugin = types.ModuleType("octoprint.plugin")
    flask = types.ModuleType("flask")

    class SettingsPlugin:
        pass

    class TemplatePlugin:
        pass

    class AssetPlugin:
        pass

    class BlueprintPlugin:
        @staticmethod
        def route(*_args, **_kwargs):
            def decorator(func):
                return func
            return decorator

    plugin.SettingsPlugin = SettingsPlugin
    plugin.TemplatePlugin = TemplatePlugin
    plugin.AssetPlugin = AssetPlugin
    plugin.BlueprintPlugin = BlueprintPlugin
    octoprint.plugin = plugin

    flask.jsonify = lambda data: data

    class _Request:
        @staticmethod
        def get_json(silent=True):
            return {}

    flask.request = _Request()

    sys.modules["octoprint"] = octoprint
    sys.modules["octoprint.plugin"] = plugin
    sys.modules["flask"] = flask


install_octoprint_stub()
import octoprint_network_settings as plugin  # noqa: E402


def check_backend_merge():
    calls = []

    def fake_run(args, timeout=10):
        calls.append((args, timeout))
        if args == ["status"]:
            return {"interface": "wlan0", "state": "connected", "connection": "HomeWiFi"}, 0
        if args == ["read"]:
            return {
                "ssid": "HomeWiFi",
                "ipv4_method": "manual",
                "address": "192.168.1.44/24",
                "gateway": "192.168.1.1",
                "dns": "1.1.1.1,8.8.8.8",
            }, 0
        raise AssertionError(args)

    old_run = plugin._run
    plugin._run = fake_run
    try:
        data, ok = plugin._get_network_info()
        assert ok is True
        assert data["state"] == "connected"
        assert data["ssid"] == "HomeWiFi"
        assert data["ipv4_method"] == "manual"
        assert data["address"] == "192.168.1.44/24"
        assert len(calls) == 2
    finally:
        plugin._run = old_run


def check_disconnected_status_still_loads():
    def fake_run(args, timeout=10):
        if args == ["status"]:
            return {"interface": "wlan0", "state": "disconnected", "connection": ""}, 0
        if args == ["read"]:
            return {"error": "no active connection on wlan0"}, 1
        raise AssertionError(args)

    old_run = plugin._run
    plugin._run = fake_run
    try:
        data, ok = plugin._get_network_info()
        assert ok is True
        assert data["state"] == "disconnected"
        assert data["config_error"] == "no active connection on wlan0"
    finally:
        plugin._run = old_run


def check_save_dispatch():
    seen = []

    def fake_run(args, timeout=10):
        seen.append(args)
        return {"ok": True}, 0

    old_run = plugin._run
    plugin._run = fake_run
    try:
        data, rc = plugin._save_settings({
            "ssid": "Lab",
            "password": "secret123",
            "mode": "manual",
            "address": "192.168.0.50/24",
            "gateway": "192.168.0.1",
            "dns": "8.8.8.8,1.1.1.1",
        })
        assert rc == 0 and data["ok"] is True
        assert seen == [[
            "save-wifi-static",
            "Lab",
            "secret123",
            "192.168.0.50/24",
            "192.168.0.1",
            "8.8.8.8,1.1.1.1",
        ]]

        data, rc = plugin._save_settings({"mode": "nope"})
        assert rc == 1
        assert data["error"] == "mode must be auto or manual"
    finally:
        plugin._run = old_run


def check_apply_dispatch_and_restore():
    seen = []

    def fake_run(args, timeout=10):
        seen.append((args, timeout))
        if args == ["backup-wifi"]:
            return {"ok": True, "backup": "/tmp/last.nmconnection"}, 0
        if args == ["save-wifi-dhcp", "Lab", "secret123"]:
            return {"ok": True, "ssid": "Lab", "ipv4_method": "auto"}, 0
        if args == ["apply-wifi"]:
            return {"ok": True, "interface": "wlan0", "connection": "Lab"}, 0
        if args == ["restore-wifi"]:
            return {"ok": True, "restored": "last.nmconnection"}, 0
        raise AssertionError(args)

    old_run = plugin._run
    plugin._run = fake_run
    try:
        data, rc = plugin._apply_settings({
            "ssid": "Lab",
            "password": "secret123",
            "mode": "auto",
        })
        assert rc == 0
        assert data["backup"] == "/tmp/last.nmconnection"
        assert data["connection"] == "Lab"
        assert seen[:3] == [
            (["backup-wifi"], 10),
            (["save-wifi-dhcp", "Lab", "secret123"], 10),
            (["apply-wifi"], 30),
        ]

        data, rc = plugin._restore_settings()
        assert rc == 0
        assert data["restored"] == "last.nmconnection"
        assert seen[3] == (["restore-wifi"], 30)
    finally:
        plugin._run = old_run


def check_ui_files():
    template = open(os.path.join(ROOT, "octoprint_network_settings", "templates", "network_settings_settings.jinja2"), encoding="utf-8").read()
    js = open(os.path.join(ROOT, "octoprint_network_settings", "static", "js", "network_settings.js"), encoding="utf-8").read()

    for needle in [
        "State",
        "Active SSID",
        "IPv4 Address",
        "Gateway",
        "DNS",
        "Mode",
        "SSID",
        "Password",
        "Address / CIDR",
        "Save &amp; Restart Network",
        "Revert to Last Backup",
        "may temporarily disconnect OctoPrint",
        "Neither action restarts OctoPrint",
    ]:
        assert needle in template, needle

    for needle in [
        'plugin/network_settings/status',
        'plugin/network_settings/save',
        'plugin/network_settings/apply',
        'plugin/network_settings/restore',
        'self.mode() === "manual"',
        'Save & Restart Network failed:',
        'Restore failed:',
    ]:
        assert needle in js, needle


if __name__ == "__main__":
    check_backend_merge()
    check_disconnected_status_still_loads()
    check_save_dispatch()
    check_apply_dispatch_and_restore()
    check_ui_files()
    print("smoke_check.py: ok")
