.PHONY: builder build-vm build-all-vm fetch dts _check-env clean build build-all \
        octoprint docker zoraxy verify-octoprint \
        kernel-env-check modules kernel-env kernel-modules \
        plugins deploy-led

# ponytail: pass PROFILE=<name> on the make command line, e.g. make build PROFILE=octoprint
export PROFILE ?=
SSH ?= ssh

builder:
	vagrant up
	vagrant rsync
	vagrant ssh -c "cd /app && sudo bash"
	@echo "[msm8916] Tip: run 'make fetch' on the host to copy build artifacts to files/."

# Non-interactive build from the host; fetch artifacts via SSH after the build.
build-vm:
	vagrant up
	vagrant rsync
	vagrant ssh -c "cd /app && sudo make build PROFILE=$(PROFILE)"
	$(MAKE) fetch

build-all-vm:
	vagrant up
	vagrant rsync
	vagrant ssh -c "cd /app && sudo make build-all PROFILE=$(PROFILE)"
	$(MAKE) fetch

fetch:
	@mkdir -p files
	vagrant ssh -c "cd /app/files && tar cf - *.img.gz *.tgz *.zip *.bin dtbs/ 2>/dev/null" | tar xf - -C files/
	@echo "[+] Fetched to files/:"
	@ls -lh files/

dts:
	./scripts/generate_dts.sh ./files

_check-env:
	@systemd-detect-virt -q 2>/dev/null || [ -f /proc/1/cgroup ] || { echo "ERROR: Run this inside the builder VM (make builder) or a CI environment"; exit 1; }

clean: _check-env
	rm -rf files .kernel-dts saved

build: _check-env
	rm -rf files
	mkdir -p files
	./scripts/generate_dts.sh ./files
	./scripts/generate_alpine_rootfs.sh ./files
	./scripts/generate_images.sh ./files

build-all: build
	./scripts/generate_firmware.sh files/firmware.zip
	./scripts/generate_gpt_table.sh files/gpt_both0.bin

# ponytail: static aliases — add new profile here when profiles/*.env grows
octoprint: _check-env
	$(MAKE) build-all PROFILE=octoprint

docker: _check-env
	$(MAKE) build-all PROFILE=docker

zoraxy: _check-env
	$(MAKE) build-all PROFILE=zoraxy

verify-octoprint:
	./stacks/verify-octoprint.sh

# USB serial modules for OctoPrint
kernel-env-check:
	bash scripts/validate-kernel-env.sh

modules: _check-env
	bash scripts/make_modules.sh

kernel-env: _check-env
	bash scripts/setup-kernel-build.sh

kernel-modules: modules

# Plugin zip artifacts (host-side, no VM needed)
plugins:
	cd plugins/octoprint-led-status && \
	  mkdir -p dist && \
	  zip -r dist/OctoPrint-LedStatus-1.0.0.zip setup.py smoke_check.py octoprint_led_status/
	@echo "[+] plugins/octoprint-led-status/dist/OctoPrint-LedStatus-1.0.0.zip"

# ponytail: live-device install — make deploy-led HOST=root@<device-ip>
deploy-led: plugins
	@tmp=$$(mktemp -d); \
	  cp plugins/octoprint-led-status/dist/OctoPrint-LedStatus-1.0.0.zip $$tmp/; \
	  cp plugins/octoprint-led-status/helper/led-helper $$tmp/; \
	  cp plugins/octoprint-led-status/sudoers/octoprint-led $$tmp/; \
	  printf '%s\n' \
	    '#!/bin/sh' \
	    'set -e' \
	    'export PATH=/sbin:/bin:/usr/sbin:/usr/bin' \
	    '/opt/octoprint/venv/bin/pip install --force-reinstall --no-deps /tmp/OctoPrint-LedStatus-1.0.0.zip' \
	    'mkdir -p /usr/local/sbin /etc/sudoers.d' \
	    'install -o root -g root -m 0755 /tmp/led-helper /usr/local/sbin/led-helper' \
	    'install -o root -g root -m 0440 /tmp/octoprint-led /etc/sudoers.d/octoprint-led' \
	    '{ command -v visudo >/dev/null 2>&1 && visudo -c || true; }' \
	    'rc-service octoprint restart' \
	    > $$tmp/deploy-led.sh; \
	  tar -C $$tmp -cf - . | $(SSH) $(HOST) 'tar xf - -C /tmp'; \
	  rm -rf $$tmp
	$(SSH) $(HOST) 'sudo -n sh /tmp/deploy-led.sh'
