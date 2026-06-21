# ponytail: pass PROFILE=<name> on the make command line, e.g. make build PROFILE=octoprint
export PROFILE ?=

builder:
	vagrant up
	vagrant rsync
	vagrant ssh -c "cd /app && sudo bash"
	@echo "[msm8916] Tip: run 'make fetch' on the host to copy build artifacts to files/."

# Non-interactive build from the host; fetch artifacts via SSH after the build.
build-vm:
	vagrant up
	vagrant rsync
	vagrant ssh -c "cd /app && sudo make build"
	$(MAKE) fetch

build-all-vm:
	vagrant up
	vagrant rsync
	vagrant ssh -c "cd /app && sudo make build-all"
	$(MAKE) fetch

fetch:
	@mkdir -p files
	vagrant ssh -c "cd /app/files && tar cf - *.img.gz *.zip *.bin dtbs/ 2>/dev/null" | tar xf - -C files/
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

# Kernel build environment for out-of-tree modules (issue-002)
kernel-env-check:
	bash scripts/validate-kernel-env.sh

kernel-env: _check-env
	bash scripts/setup-kernel-build.sh
