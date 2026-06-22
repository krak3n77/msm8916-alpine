from setuptools import setup, find_packages

setup(
    name="OctoPrint-LedStatus",
    version="1.0.0",
    description="Visual LED feedback for printer states via led-helper",
    packages=find_packages(),
    install_requires=["OctoPrint"],
    entry_points={
        "octoprint.plugin": [
            "led_status = octoprint_led_status"
        ]
    },
)
