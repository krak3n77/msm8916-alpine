# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "perk/ubuntu-2204-arm64"
  config.vm.hostname = "msm8916-builder"
  config.vm.boot_timeout = 600

  config.vm.network "forwarded_port", guest: 22, host: 50122, id: "ssh"

  config.vm.provider "qemu" do |qe|
    qe.memory = "4G"
    qe.smp = "4"
    qe.arch = "aarch64"
    qe.machine = "virt,accel=hvf,highmem=on"
    qe.cpu = "host"
    qe.net_device = "virtio-net-pci"
  end

  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.synced_folder ".", "/app", type: "rsync",
    rsync__exclude: [".git/", "files/", "kernel-build/"]

  # ponytail: vagrant-qemu uses SLIRP user networking — NFS and private_network are
  # silently ignored. SSH-over-port-forward is the only host↔guest transport.
  # Artifact copy is done explicitly by 'make fetch' (called by build-vm / build-all-vm).
  # No trigger here: 'make fetch' calls 'vagrant ssh -c', which would re-fire any
  # :ssh_run trigger, causing unbounded recursion.

  config.vm.provision "shell", inline: <<-SHELL
    export DEBIAN_FRONTEND=noninteractive
    cd /app
    chmod +x scripts/install_dependencies.sh
    TARGETARCH=$(dpkg --print-architecture) scripts/install_dependencies.sh
  SHELL
end
