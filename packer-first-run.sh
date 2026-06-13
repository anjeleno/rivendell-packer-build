#!/bin/bash
# First-time setup for a fresh "packer builder" droplet.
#
# Usage (on a brand-new Ubuntu droplet, before this repo is cloned):
#   export DIGITALOCEAN_TOKEN="dop_v1_..."
#   curl -fsSL https://raw.githubusercontent.com/anjeleno/rivendell-packer-build/main/packer-first-run.sh | bash
#
# Or copy/paste the contents directly into an SSH session.
#
# Installs Packer + Git, clones this repo to /root/rivendell-build, and runs
# the build. For subsequent builds on the same droplet, use
# /root/rivendell-build/packer-rebuild.sh instead.

set -e

: "${DIGITALOCEAN_TOKEN:?Set DIGITALOCEAN_TOKEN before running this script}"
export DIGITALOCEAN_TOKEN

# Wait for cloud-init and background apt lock
cloud-init status --wait || true
systemctl stop unattended-upgrades || true
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 5; done
dpkg --configure -a || true

# Install HashiCorp Packer and Git
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y packer git

# Clone the repo containing the scripts, HCL blueprint, and APPS folder
rm -rf /root/rivendell-build
git clone https://github.com/anjeleno/rivendell-packer-build.git /root/rivendell-build
cd /root/rivendell-build
chmod +x *.sh

# Build
packer init rivendell.pkr.hcl
packer build rivendell.pkr.hcl
