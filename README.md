# Rivendell Golden Image Packer Build

This repository contains an automated HashiCorp Packer blueprint and a universal unattended installation script for deploying a fully-customized Rivendell audio automation environment (v4.4.1). 

It includes the custom "MP3 Ingestion" codebase patch, custom SQLite imports, and auto-configured JACK, Icecast, and Live Remote environments.

## How to Build the Image on DigitalOcean (Zero-Touch Automation)

You do not need to install anything on your local computer to build this image. You can "factory bake" the image by spinning up a cheap droplet on DigitalOcean that builds the final image and then turns itself off.

1. Generate a **Personal Access Token** (API Key) in your DigitalOcean dashboard.
2. Go to DigitalOcean and click **Create Droplet**.
3. Choose the cheapest **Ubuntu** droplet available (e.g. $4/month).
4. In the **Advanced Options** section during Droplet creation, check the box for **Add user data** (or "Startup scripts").
5. Copy and paste the script below into the text box.
   **(Make sure to replace `dop_v1_YOUR_TOKEN_HERE` with your actual DigitalOcean API Key!)**

```bash
#!/bin/bash
# Autonomous Packer Factory - Startup Script

# 1. Inject your DigitalOcean API Token
export DIGITALOCEAN_TOKEN="dop_v1_YOUR_TOKEN_HERE"

# 2. Install HashiCorp Packer and Git natively
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update
apt-get install -y packer git

# 3. Pull your repository containing the scripts, HCL blueprint, and APPS folder
git clone https://github.com/anjeleno/rivendell-packer-build.git /root/rivendell-build
cd /root/rivendell-build

# Ensure the installer script is executable
chmod +x rivendell-auto-install.sh

# 4. Execute the Packer Build (routing output to a log file just in case)
packer build rivendell.pkr.hcl > /root/packer-build.log 2>&1

# 5. Shut down the droplet when the build is completely finished
poweroff
```

6. Click **Create Droplet**. 

### What happens next?
You can close the window and walk away. The droplet will automatically boot up, install Packer, and spin up a *second* temporary build server. The build server will compile Rivendell, apply your MP3 patches, and ingest your configurations. 

When it finishes, Packer will save a pristine Snapshot named `rivendell-4.4.1-custom-mp3-[timestamp]` to your DigitalOcean account (under the **Images** -> **Snapshots** tab) and destroy the temporary build server. 

Finally, the $4 factory droplet will power itself off. Once you see the dot turn gray in your DigitalOcean dashboard, the build is complete. You can delete the powered-off droplet and start deploying your brand new Golden Image Snapshot to production!
