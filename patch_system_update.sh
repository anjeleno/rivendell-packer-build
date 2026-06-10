sed -i '/system_update() {/,/mark_step_completed "system_update"/c\
system_update() {\
    echo "Waiting for cloud-init to complete..."\
    sudo cloud-init status --wait || true\
\
    echo "Stopping unattended-upgrades to prevent apt lock conflicts..."\
    sudo systemctl stop unattended-upgrades || true\
    sudo systemctl disable unattended-upgrades || true\
\
    echo "Waiting for apt locks to release..."\
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do\
        echo "Apt is locked. Waiting 10 seconds..."\
        sleep 10\
    done\
\
    echo "Fixing any interrupted dpkg states..."\
    sudo dpkg --configure -a || true\
\
    echo "Updating system..."\
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -y\
    sudo DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"\
    mark_step_completed "system_update"\
' /root/rivendell-cloud/rivendell-auto-install.sh
sed -i '/provisioner "shell" {/,/]/c\
  provisioner "shell" {\
    inline = [\
      "mkdir -p /opt/APPS",\
      "cloud-init status --wait || true",\
      "sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades || true",\
      "echo \"DPkg::Lock::Timeout \\\"600\\\";\" | sudo tee /etc/apt/apt.conf.d/99timeout",\
    ]\
  }' /root/rivendell-cloud/rivendell.pkr.hcl
