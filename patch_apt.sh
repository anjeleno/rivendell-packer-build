sed -i 's/sudo apt-get update/sudo apt-get -o Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" update/g' /root/rivendell-cloud/rivendell-auto-install.sh
sed -i 's/sudo apt-get install/sudo apt-get -o Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install/g' /root/rivendell-cloud/rivendell-auto-install.sh
