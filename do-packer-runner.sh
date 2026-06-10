#!/bin/bash
# Autonomous Packer Factory - Startup Script

# 1. Inject your DigitalOcean API Token
export DIGITALOCEAN_TOKEN="dop_v1_YOUR_TOKEN_HERE"

# 2. Install HashiCorp Packer and Git natively
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update
apt-get install -y packer git

# 3. Pull your repository containing the scripts, HCL blueprint, and APPS folder
git clone https://github.com/anjeleno/rivendell-packer-build.git /root/rivendell-build
cd /root/rivendell-build

# Ensure the installer script is executable
chmod +x rivendell-auto-install.sh

# 4. Initialize Packer (Download DigitalOcean plugin)
packer init rivendell.pkr.hcl

# 5. Execute the Packer Build (routing output to a log file just in case)
packer build rivendell.pkr.hcl > /root/packer-build.log 2>&1

# 6. Shut down the droplet when the build is completely finished
poweroff
