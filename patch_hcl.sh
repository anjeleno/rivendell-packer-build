sed -i '/"mkdir -p \/opt\/APPS"/a \      "echo '\''DPkg::Lock::Timeout \\"600\\";'\'' | sudo tee /etc/apt/apt.conf.d/99timeout",' /root/rivendell-cloud/rivendell.pkr.hcl
sed -i '/"mkdir -p \/opt\/APPS"/a \      "sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer || true",' /root/rivendell-cloud/rivendell.pkr.hcl
