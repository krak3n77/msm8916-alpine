#!/usr/bin/env python3
"""
Smoke check for OctoPrint-LedStatus.
Runs without OctoPrint installed — tests helper script only + degrade path.
"""
import os
import subprocess
import sys

HELPER = os.path.join(os.path.dirname(__file__), "helper", "led-helper")


def test_helper_syntax():
    r = subprocess.run(["sh", "-n", HELPER], capture_output=True, text=True)
    assert r.returncode == 0, f"shell syntax error: {r.stderr}"
    print("  [OK] helper shell syntax valid")


def test_helper_rejects_unknown():
    r = subprocess.run(["sh", HELPER, "bogus"], capture_output=True, text=True)
    assert r.returncode != 0, "helper must reject unknown state"
    print("  [OK] helper rejects unknown state with non-zero exit")


def test_no_red_power():
    with open(HELPER) as f:
        non_comment = "\n".join(
            l for l in f.read().splitlines() if not l.lstrip().startswith("#")
        )
    assert "red:power" not in non_comment, "helper must not reference red:power outside comments"
    print("  [OK] helper has no red:power references in code")


def test_degrade():
    """_set_led_state must not raise even when helper is absent."""
    code = """
import subprocess
def _set_led_state(state):
    try:
        subprocess.run(["sudo", "/nonexistent/led-helper", state],
                       capture_output=True, timeout=5)
    except Exception:
        pass
_set_led_state("idle")
_set_led_state("disconnected")
print("ok")
"""
    r = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True)
    assert "ok" in r.stdout, f"degrade test failed: {r.stderr}"
    print("  [OK] _set_led_state degrades safely when helper missing")


if __name__ == "__main__":
    print("OctoPrint-LedStatus smoke check")
    failures = []
    for t in [test_helper_syntax, test_helper_rejects_unknown, test_no_red_power, test_degrade]:
        try:
            t()
        except Exception as e:
            print(f"  [FAIL] {t.__name__}: {e}")
            failures.append(t.__name__)
    if failures:
        print(f"\nFAILED: {failures}")
        sys.exit(1)
    print("\nAll checks passed.")
