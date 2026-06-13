# Rivendell Golden Image Packer Build

This repository contains an automated HashiCorp Packer blueprint and a universal unattended installation script for deploying a fully-customized Rivendell audio automation environment (v4.4.1). 

It includes the custom "MP3 Ingestion" codebase patch, custom SQLite imports, and auto-configured JACK, Icecast, and Live Remote environments.

## How to Build the Image on DigitalOcean (Zero-Touch Automation)

You do not need to install anything on your local computer to build this image. You can "factory bake" the image by spinning up a cheap droplet on DigitalOcean that builds the final image and then turns itself off.

1. Generate a **Personal Access Token** (API Key) in your DigitalOcean dashboard.
2. Go to DigitalOcean and click **Create Droplet**.
3. Choose the cheapest **Ubuntu** droplet available (e.g. $4/month).
4. Select your saved **SSH Key** (this is required by DO and will not interfere with the build).
5. In the **Advanced Options** section during Droplet creation, check the box for **Add user data** (or "Startup scripts").
6. Copy and paste the script below into the text box.
   **(Make sure to replace `dop_v1_YOUR_TOKEN_HERE` with your actual DigitalOcean API Key!)**

```bash
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
# We use '&& poweroff' so that if Packer FAILS, the droplet stays online.
# This allows you to SSH into the factory droplet and cat /root/packer-build.log to read the exact error.
packer build rivendell.pkr.hcl > /root/packer-build.log 2>&1 && poweroff
```

7. Click **Create Droplet**. 

### What happens next?
You can close the window and walk away. The droplet will automatically boot up, install Packer, and spin up a *second* temporary build server. The build server will compile Rivendell, apply your MP3 patches, and ingest your configurations. 

When it finishes, Packer will save a pristine Snapshot named `rivendell-4.4.1-custom-mp3-[timestamp]` to your DigitalOcean account (under the **Images** -> **Snapshots** tab) and destroy the temporary build server. 

Finally, the factory droplet will power itself off. Once you see the dot turn gray in your DigitalOcean dashboard, the build is complete. You can delete the powered-off droplet and start deploying your brand new Golden Image Snapshot to production!

## Manual / Debug Build

If you want to watch the build process live, catch any errors without the droplet shutting off, or if the zero-touch script fails, do the following:

1. Spin up a new baseline Ubuntu Droplet on DigitalOcean. Do **NOT** use a Startup Script. Ensure your SSH key is selected.
2. SSH into the Droplet: `ssh root@<DROPLET_IP>`
3. Export your token, then run `packer-first-run.sh`. This installs Packer/Git, clones this repo to `/root/rivendell-build`, and runs the build:

```bash
export DIGITALOCEAN_TOKEN="dop_v1_YOUR_TOKEN_HERE"
curl -fsSL https://raw.githubusercontent.com/anjeleno/rivendell-packer-build/main/packer-first-run.sh | bash
```

### Subsequent Builds (same droplet)

Once Packer/Git are installed from the first run, you don't need to repeat
steps 2-5. Just run the included `packer-rebuild.sh`, which wipes
`/root/rivendell-build`, does a fresh `git clone` of the latest committed
changes, and re-runs the build:

```bash
export DIGITALOCEAN_TOKEN="dop_v1_YOUR_TOKEN_HERE"
cd /root/rivendell-build
./packer-rebuild.sh
```

# Reset + Pull changes from repo after patching if build fails with erros
```
git fetch --all
git reset --hard origin/main
packer init rivendell.pkr.hcl
packer build rivendell.pkr.hcl
```