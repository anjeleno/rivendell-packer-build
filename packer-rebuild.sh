#!/bin/bash
# Re-run the Packer build on a "packer builder" droplet that already has
# Packer/Git installed from a previous run.
#
# Usage:
#   export DIGITALOCEAN_TOKEN="dop_v1_..."
#   ./packer-rebuild.sh
#
# Wipes any existing /root/rivendell-build and does a fresh `git clone`, so
# the build always runs against the latest committed changes.

set -e

: "${DIGITALOCEAN_TOKEN:?Set DIGITALOCEAN_TOKEN before running this script}"
export DIGITALOCEAN_TOKEN

# Wait for cloud-init and background apt lock
cloud-init status --wait || true
systemctl stop unattended-upgrades || true
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 5; done
dpkg --configure -a || true
export DEBIAN_FRONTEND=noninteractive

# Fresh clone of the latest scripts, HCL blueprint, and APPS folder
rm -rf /root/rivendell-build
git clone https://github.com/anjeleno/rivendell-packer-build.git /root/rivendell-build
cd /root/rivendell-build
chmod +x *.sh

# Re-run the build
packer init rivendell.pkr.hcl
packer build rivendell.pkr.hcl
