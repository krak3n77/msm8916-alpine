from setuptools import setup, find_packages

setup(
    name="OctoPrint-NetworkSettings",
    version="1.0.0",
    description="WiFi / IP configuration via NetworkManager (nm-wrapper)",
    packages=find_packages(),
    package_data={"octoprint_network_settings": ["templates/*", "static/js/*"]},
    install_requires=["OctoPrint"],
    entry_points={
        "octoprint.plugin": [
            "network_settings = octoprint_network_settings"
        ]
    },
)
