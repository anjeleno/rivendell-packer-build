#!/bin/bash
# Autonomous Packer Factory - Startup Script

# 1. Inject your DigitalOcean API Token
export DIGITALOCEAN_TOKEN="dop_v1_YOUR_TOKEN_HERE"

# 2. Wait for cloud-init and background apt lock
cloud-init status --wait || true
systemctl stop unattended-upgrades || true
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 5; done
dpkg --configure -a || true

# 3. Install HashiCorp Packer and Git natively
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y packer git

# 4. Pull your repository containing the scripts, HCL blueprint, and APPS folder
git clone https://github.com/anjeleno/rivendell-packer-build.git /root/rivendell-build
cd /root/rivendell-build
chmod +x *.sh

# 5. Initialize Packer (Download DigitalOcean plugin)
packer init rivendell.pkr.hcl

# 6. Execute the Packer Build (routing output to a log file just in case)
packer build rivendell.pkr.hcl > /root/packer-build.log 2>&1 && poweroff
