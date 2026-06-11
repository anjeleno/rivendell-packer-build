#!/bin/bash
# Rivendell Universal Auto-Install Script (Unattended)
# Version: 0.25.0 (Dual-Architecture Golden Image Build)
# Date: 2026-06-10
# Description: Automates Rivendell deployment cleanly on Ubuntu 24.04/26.04.
#              Automatically detects architecture (AMD64 vs ARM64).
#              Bypasses Paravel repository limitations on ARM64 by manually 
#              scaffolding the system environment prior to local source compilation.

set -e

# Enforce completely non-interactive front-end for automated builds
export DEBIAN_FRONTEND=noninteractive

# Configuration variables (Automated defaults for Golden Image deployment)
INSTALL_TYPE="2" # Default to Server Mode. Override via env if needed.
RD_PASSWORD="YourSecurePassword123!"

STEP_DIR="/home/rd/rivendell_install_steps"
INITIAL_STEPS_COMPLETED="/home/rd/initial_steps_completed"
TMP_STEP_DIR="/tmp/rivendell_install_steps"

ensure_step_dir() {
    if [ ! -d "$STEP_DIR" ]; then
        sudo mkdir -p "$STEP_DIR"
        sudo chown rd:rd "$STEP_DIR"
    fi
}

ensure_tmp_step_dir() {
    if [ ! -d "$TMP_STEP_DIR" ]; then
        sudo mkdir -p "$TMP_STEP_DIR"
    fi
}

step_completed() {
    local step_name="$1"
    if [ -f "$STEP_DIR/$step_name" ] || [ -f "$TMP_STEP_DIR/$step_name" ]; then
        return 0
    else
        return 1
    fi
}

mark_step_completed() {
    local step_name="$1"
    if [ "$(whoami)" != "rd" ]; then
        touch "$TMP_STEP_DIR/$step_name"
    else
        touch "$STEP_DIR/$step_name"
    fi
}

ensure_rd_user() {
    if [ "$(whoami)" != "rd" ]; then
        echo "Switching context to 'rd' user..."
        exit 1
    fi
}

ensure_mysql_running() {
    if ! sudo systemctl is-active --quiet mariadb; then
        sudo systemctl start mariadb
    fi
}

extract_mysql_password() {
    echo "Extracting MySQL password..."
    MYSQL_PASSWORD=$(awk -F= '/\[mySQL\]/{flag=1;next}/\[/{flag=0}flag && /Password=/{print $2;exit}' /etc/rd.conf)
    if [ -z "$MYSQL_PASSWORD" ]; then
        # Default fallback password if file generation was entirely decoupled
        MYSQL_PASSWORD="rduser"
    fi
    mark_step_completed "extract_mysql_password"
}

import_sql_backup() {
    echo "Dropping default tables and importing clean database environment..."
    DB_HOST="localhost"
    DB_USER="rduser"
    DB_PASS="$MYSQL_PASSWORD"
    DB_NAME="Rivendell"
    BACKUP_FILE="/home/rd/imports/APPS/RDDB_v430_Cloud.sql"

    execute_mariadb_command() {
        mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" "$@" 2>&1
    }

    if [ -f "$BACKUP_FILE" ]; then
        execute_mariadb_command -e "SET FOREIGN_KEY_CHECKS = 0; DROP TABLE IF EXISTS \`*\`; SET FOREIGN_KEY_CHECKS = 1;"
        mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$BACKUP_FILE" 2>&1
        execute_mariadb_command -e "ALTER TABLE DROPBOXES ADD COLUMN IF NOT EXISTS CODING_FORMAT int(11) NOT NULL default '-1' AFTER CREATE_GROUP;"
    else
        echo "Backup database payload not discovered. Skipping import."
    fi
    mark_step_completed "import_sql_backup"
}

update_backup_script() {
    if [ -f /home/rd/imports/APPS/sql/daily_db_backup.sh ]; then
        sed -i "s|SQL_PASSWORD_GOES_HERE|${MYSQL_PASSWORD}|" /home/rd/imports/APPS/sql/daily_db_backup.sh
        sed -i 's/ -p /-p/' /home/rd/imports/APPS/sql/daily_db_backup.sh
    fi
    mark_step_completed "update_backup_script"
}

enable_firewall() {
    echo "Enforcing baseline firewall rules..."
    sudo apt-get -o Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y ufw
    sudo ufw allow 8000/tcp
    sudo ufw allow ssh
    sudo ufw --force enable
    mark_step_completed "enable_firewall"
}

harden_ssh() {
    # Unattended execution bypasses interactive warning confirmations
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config-BAK
    sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config
    sudo systemctl restart ssh
    mark_step_completed "harden_ssh"
}

configure_icecast() {
    if [ -f /etc/icecast2/icecast.xml ] && [ -f /home/rd/imports/APPS/icecast.xml ]; then
        sudo cp -f /home/rd/imports/APPS/icecast.xml /etc/icecast2/icecast.xml
        sudo chown root:icecast /etc/icecast2/icecast.xml
        sudo chmod 640 /etc/icecast2/icecast.xml
    fi
    mark_step_completed "configure_icecast"
}

enable_icecast() {
    sudo systemctl daemon-reload
    sudo systemctl enable icecast2 || true
    sudo systemctl start icecast2 || true
    mark_step_completed "enable_icecast"
}

disable_pulseaudio() {
    sudo killall pulseaudio || true
    sudo usermod -aG audio rd || true
    sudo usermod -aG audio rivendell || true
    
    sudo tee -a /etc/security/limits.conf <<EOL
@audio      hard      rtprio          90
@audio      hard      memlock     unlimited
EOL
    mark_step_completed "disable_pulseaudio"
}

fix_qt5() {
    sudo ln -sf /home/rd/.Xauthority /root/.Xauthority
    mark_step_completed "fix_qt5"
}

restore_bashrc() {
    if [ -f /home/rd/.bashrc.bak ]; then
        sudo mv /home/rd/.bashrc.bak /home/rd/.bashrc
        sudo chown rd:rd /home/rd/.bashrc
    fi
    mark_step_completed "restore_bashrc"
}

system_update() {
    echo "Waiting for cloud-init to complete..."
    sudo cloud-init status --wait || true

    echo "Stopping unattended-upgrades to prevent apt lock conflicts..."
    sudo systemctl stop unattended-upgrades || true
    sudo systemctl disable unattended-upgrades || true

    echo "Waiting for apt locks to release..."
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        echo "Apt is locked. Waiting 10 seconds..."
        sleep 10
    done

    echo "Fixing any interrupted dpkg states..."
    sudo dpkg --configure -a || true

    echo "Updating system..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    mark_step_completed "system_update"


}

set_hostname() {
    sudo hostnamectl set-hostname onair
    sudo sed -i "/127.0.1.1/c\127.0.1.1\tonair" /etc/hosts
    mark_step_completed "set_hostname"
}

create_rd_user() {
    if ! id -u rd >/dev/null 2>&1; then
        sudo adduser --disabled-password --gecos "rd,Rivendell Audio,,," --home /home/rd rd
        sudo usermod -aG sudo rd
        echo "rd ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/rd >/dev/null
        echo "rd:${RD_PASSWORD}" | sudo chpasswd
        sudo chown -R rd:rd /home/rd
        sudo chmod 755 /home/rd
    fi
    mark_step_completed "create_rd_user"
}

copy_working_directory() {
    if [ ! -d "/home/rd/Rivendell-Cloud" ]; then
        sudo mkdir -p /home/rd/Rivendell-Cloud
        if [ -d "/opt/APPS" ]; then
            sudo cp -r /opt/APPS /home/rd/Rivendell-Cloud/APPS
        fi
        sudo chown -R rd:rd /home/rd/Rivendell-Cloud
    fi
    mark_step_completed "copy_working_directory"
}

backup_bashrc() {
    if [ -f /home/rd/.bashrc ]; then
        sudo cp /home/rd/.bashrc /home/rd/.bashrc.bak
        sudo chown rd:rd /home/rd/.bashrc.bak
    fi
    mark_step_completed "backup_bashrc"
}

configure_shell_profile() {
    if ! grep -q "cd /home/rd/Rivendell-Cloud" /home/rd/.bashrc; then
        echo "cd /home/rd/Rivendell-Cloud" | sudo tee -a /home/rd/.bashrc > /dev/null
    fi
    mark_step_completed "configure_shell_profile"
}

install_tasksel() {
    sudo apt-get -o Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y tasksel
    mark_step_completed "install_tasksel"
}

install_mate() {
    # Non-interactive target execution for MATE environment installation
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-mate-desktop
    mark_step_completed "install_mate"
}

install_xrdp() {
    sudo apt-get -o Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y xrdp dbus-x11
    mark_step_completed "install_xrdp"
}

configure_xrdp() {
    echo "mate-session" | sudo tee /home/rd/.xsession > /dev/null
    sudo chown rd:rd /home/rd/.xsession
    sudo systemctl restart xrdp
    mark_step_completed "configure_xrdp"
}

set_mate_default() {
    sudo update-alternatives --set x-session-manager /usr/bin/mate-session || true
    mark_step_completed "set_mate_default"
}

install_rivendell() {
    # 0. Ensure the config file exists before trying to read it
    if [ ! -f /etc/rd.conf ]; then
        # Ensure the group exists first
        sudo groupadd -g 514 rivendell || true
        
        sudo tee /etc/rd.conf > /dev/null <<EOF
[mySQL]
Loginname=rduser
Password=rduser
Database=Rivendell
Hostname=localhost
EOF
        sudo chown rd:rivendell /etc/rd.conf
        sudo chmod 644 /etc/rd.conf
    fi

    UBUNTU_VERSION=$(lsb_release -rs)
    SYS_ARCH=$(uname -m)

    echo "Executing Rivendell Core Target Pipeline..."

    echo "Detected Architecture: $SYS_ARCH | OS Version: $UBUNTU_VERSION"

    # FIX: Shift execution context to a globally readable directory to bypass 
    # 'pathconf: Permission denied' errors during privilege drops in Packer.
    # Placing this above the architecture check covers both AMD64 and ARM64 automatically.
    cd /tmp || exit 1

    # --- ARCHITECTURE SWAP ROUTINE ---
    # We now use the Git Clone method for ALL architectures to maintain consistency
    # and guarantee that your custom patches are applied every time.
    
    echo "Executing Rivendell Core Build Pipeline..."
    
    # Keep the manual system dependencies for both architectures
    sudo apt-get update
    sudo apt-get install -y mariadb-server mariadb-client apache2 libapache2-mod-cext \
                         libqt5sql5-mysql cutmp3 vorbis-tools flac lame normalize-audio \
                         libsoundtouch6 shared-mime-info sudo

    # ... (Keep your groupadd and limits.d logic here) ...

    # Skip the 'wget' and './install_rivendell.sh' entirely.
    # Proceed directly to the # --- SOURCE BUILD & PATCH INTERCEPT --- section.

        # FIX: The Paravel script pulls down heavy desktop packages. 
        # Purge them immediately after the installer finishes to shrink the Golden Image.
        echo "Purging unnecessary desktop bloatware..."
        sudo apt-get purge -y libreoffice* evolution* transmission* rhythmbox* celluloid* hexchat* laptop-detect
        sudo apt-get autoremove --purge -y
        sudo apt-get clean

    elif [[ "$SYS_ARCH" == "aarch64" || "$SYS_ARCH" == "arm64" ]]; then
        echo "Executing Custom ARM64 Engineering Path (Bypassing Architecture Block)..."
        
        # 1. Scaffold system layer dependencies manually required by base system
        sudo apt-get -o Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" update
        sudo apt-get -o Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y mariadb-server mariadb-client apache2 libapache2-mod-cext \
                                libqt5sql5-mysql cutmp3 vorbis-tools flac lame normalize-audio \
                                libsoundtouch6 shared-mime-info sudo

        # 2. Replicate standard Paravel group structural configurations
        sudo groupadd -g 514 rivendell || true
        sudo usermod -aG rivendell rd || true
        
        # 3. Provision real-time audio access controls
        sudo tee /etc/security/limits.d/rivendell.conf > /dev/null <<EOF
@rivendell       hard    rtprio          95
@rivendell       soft    rtprio          80
@rivendell       hard    memlock         unlimited
@rivendell       soft    memlock         unlimited
EOF

        # 4. Generate local sample configuration to safely trigger build steps
        if [ ! -f /etc/rd.conf ]; then
            sudo mkdir -p /etc
            sudo tee /etc/rd.conf > /dev/null <<EOF
[mySQL]
Loginname=rduser
Password=rduser
Database=Rivendell
Hostname=localhost
EOF
        fi
    fi

# --- SOURCE BUILD & PATCH INTERCEPT ---
    echo "Beginning source tree interception & compilation (Git Clone Method)..."
    
    # 1. Install necessary build-essential tools
    sudo apt-get -y install git devscripts equivs dpkg-dev build-essential debhelper patch

    # 2. Set up working directory
    BUILD_DIR="/usr/local/src/rivendell-build"
    sudo mkdir -p $BUILD_DIR
    sudo chmod 777 $BUILD_DIR
    cd $BUILD_DIR
    
    # 3. Clone and enter the repository
    rm -rf rivendell
    git clone https://github.com/ElvishArtisan/rivendell.git
    cd rivendell
    
    # 4. Checkout the tag
    git checkout tags/v4.4.1 -b v4.4.1-patched

# 5. Inject the unified MP3 patch via Base64 to avoid encoding corruption
    # The string below is the Base64 representation of the correct patch file
    echo "LS0tIGEvc2NoZW1hL3JpdmVuZGVsbC5zcWwKKysrIGIvc2NoZW1hL3JpdmVuZGVsbC5zcWwKQEAgLTQ1MCw2ICs0NTAsNyBAQAogICBERVNUSU5BVElPTiB2YXJjaGFyKDI1NSkgZGVmYXVsdCBOVUxMLAogICBDVVRfQ1JFQVRJT04gdGlueWlud(4pIE5PVCBOVUxMIGRlZmF1bHQgJzAnLAogICBDUkVBVEVfR1JPVVAgdmFyY2hhcig2NCkgZGVmYXVsdCBOVUxMLAorICBDT0RJTkdfRk9STUFUIGludDgxMSkgTk9UIE5VTEwgZGVmYXVsdCAnLTEnLAogICBBVVRPVFJJTV9MRVZFTCBpbnQoMTEpIE5PVCBOVUxMIGRlZmF1bHQgJzAnLAogICBOT1JNQUxJWkVfTEVWRUwgaW50KDExKSBOT1QgTlVMTCBkZWZhdWx0ICcwJywKICAgUFJJTUFSWSBLRVkgIChJRCkKCi0tLSBhL3V0aWxzL3JkaW1wb3J0L3JkaW1wb3J0LmNwcAorKysgYi91dGlscy9yZGltcG9ydC9yZGltcG9ydC5jcHAKQEAgLTEwNSw2ICsxMDUsNyBAQAogICBwcmludGYoIiAgLS1tZXRhZGF0YS1wYXR0ZXJuPTxwYXR0ZXJuPlxuIik7CiAgIHByaW50ZigiICAtLWF1dG90cmltLWxldmVsPTxsZXZlbD5cbiIpOwogICBwcmludGYoIiAgLS1ub3JtYWxpemF0aW9uLWxldmVsPTxsZXZlbD5cbiIpOworICBwcmludGYoIiAgLS1hdWRpby1mb3J1YXQ9PDAxMz4gKDA9UENNMTYsIDM9TVBFRyBMYXllciBJSUkpXG4iKTsKICAgcHJpbnRmKCIgIC0tdXNlLWhpZ2gtY2FydFxuIik7CiAgIHByaW50ZigiICAtLXVzZS1sb3ctY2FydFxuIik7CiB9CkBAIC0xNDAsNiArMTQxLDcgQEAKICAgaW50IG1ldGFkYXRhX29mZnNldD0wOwogICBpbnQgYXV0b3RyaW1fbGV2ZWw9MDsKICAgaW50IG5vcm1hbGl6ZV9sZXZlbD0wOworICBpbnQgYXVkaW9fZm9ybWF0PS0xOwogICBib29sIHVzZV9oaWdoX2NhcnQ9ZmFsc2U7CiAgIGJvb2wgdXNlX2xvd19jYXJ0PWZhbHNlOwogICBib29sIGRlbGV0ZV9zb3VyY2U9ZmFsc2U7CkBAIC0yMTUsNiArMjE3LDkgQEAKICAgfSBlbHNlIGlmKHN0cm5jbXAoYXJndltpXSwiLS1ub3JtYWxpemF0aW9uLWxldmVsPSIsMjIpPT0wKSB7CiAgICAgbm9ybWFsaXplX2xldmVsPWF0b2koJmFyZ3ZbaV1bMjJdKTsKIAorICB9IGVsc2UgaWYoc3RybmNtcChhcmd2W2ldLCItLWF1ZGlvLWZvcm1hdD0iLDE1KT09MCkgeworICAgIGF1ZGlvX2Zvcm1hdD1hdG9pKCZhcmd2W2ldWzE1XSk7CisKICAgfSBlbHNlIGlmKHN0cm5jbXAoYXJndltpXSwiLS11c2UtaGlnaC1jYXJ0IiwxNSk9PTApIHsKICAgICB1c2VfaGlnaF9jYXJ0PXRydWU7CiAKQEAgLTM0NSw2ICszNTAsMTEgQEAKICAgICBwb3N0LmFkZFZhcmlhYmxlKCJOT1JNQUxJWkVfTEVWRUwiLFFTdHJpbmc6Om51bWJlcihub3JtYWxpemVfbGV2ZWwpKTsKICAgfQogCisgIC8vIEFwcGVuZCB0aGUgY3VzdG9tIGZvcm1hdCBmbGFnIGlmIGV4cGxpY2l0bHkgc2V0IGJ5IHRoZSB1c2VyCisgIGlmKGF1ZGlvX2Zvcm1hdCA9PSAwIHx8IGF1ZGlvX2Zvcm1hdCA9PSAzKSB7CisgICAgIHBvc3QuYWRkVmFyaWFibGUoIkZPUk1BVCIsUVN0cmluZzo6bnVtYmVyKGF1ZGlvX2Zvcm1hdCkpOworICB9CisKICAgIGlmKHVzZV9oaWdoX2NhcnQpIHsKICAgICBwb3N0LmFkZFZhcmlhYmxlKCJVU0VfSElHSF9DQVJUIiwiMSIpOwogICB9Ci0tLSBhL3dlYi9yZHhwb3J0L3JkeHBvcnQuY3BwCisrKyBiL3dlYi9yZHhwb3J0L3JkeHBvcnQuY3BwCkBAIC00ODUsMTIgKzQ4NSwyNCBAQAogICAgICAgIHJldHVybjsKICAgIH0KIAotICAvLyBEZWZhdWx0IHRvIHRoZSBIb3N0J3MgZ2xvYmFsbHkgY29uZmlndXJlZCBBdWRpbyBGb3JtYXQKKyAgLy8gRmV0Y2ggdGhlIEhvc3QncyBnbG9iYWxseSBjb25maWd1cmVkIEF1ZGlvIEZvcm1hdAogICAgaW50IHRhcmdldEZvcm1hdCA9IGhvc3RRdWVyeS52YWx1ZSgwKS50b0ludCgpOwogCisgIC8vIElOVEVSQ0VQVDogQ2hlY2sgaWYgdGhlIGNsaWVudCBleHBsaWNpdGx5IHJlcXVlc3RlZCBhIHNwZWNpZmljIGNvZGVjIGZvcm1hdAorICAgamYoY2dpSGFzUGFyYW0oIkZPUk1BVCIpKSB7CisgICAgIGludCByZXF1ZXN0ZWRGb3JtYXQgPSBjZ2lQYXJhbUFzSW50KCJGT1JNQVQiKTsKKyAgICAgaWYocmVxdWVzdGVkRm9ybWF0ID09IDAgfHwgcmVxdWVzdGVkRm9ybWF0ID09IDMpIHsKKyAgICAgICB0YXJnZXRGb3JtYXQgPSByZXF1ZXN0ZWRGb3JtYXQ7CisgICAgICAgc3lzbG9nKExPR19JTkZPLCAicmR4cG9ydDogSG9zdCBmb3JtYXQgb3ZlcnJpZGRlbi4gVXNpbmcgZXhwbGljaXQgZm9ybWF0ICVkIiwgdGFyZ2V0Rm9ybWF0KTsKKyAgICAgfQorICAgfQorCiAgICAvLyBQcm9jZWVkIHdpdGggdGhlIHN0YW5kYXJkIHRyYW5zY29kaW5nIGFzc2lnbm1lbnQgdXNpbmcgdGFyZ2V0Rm9ybWF0CiAgICBSRFhwb3J0VHJhbnNjb2RlciB0cmFuc2NvZGVyOwogICAgdHJhbnNjb2Rlci5zZXRGb3JtYXQodGFyZ2V0Rm9ybWF0KTsKLS0tIGEvZGFlbW9ucy9yZGNhdGNodC9yZGNhdGNodC5jcHAKKysrIGIvZGFlbW9ucy9yZGNhdGNodC9yZGNhdGNodC5jcHAKQEAgLTYyMCw3ICs2MjAsNyBAQAogdm9pZCBSRENDYXRjaDo6UHJvY2Vzc0Ryb3Bib3hlcygpCiB7CiAgIFFTUUxRdWVyeSBxdWVyeTsKLSAgcXVlcnkuZXhlYygic2VsZWN0IElELCBQQVRILCBHUk9VUF9OQU1FLCBBVVRPVFJJTV9MRVZFTCwgTk9STUFMSVpFX0xFVkVMIEZST00gRFJPUEJPWEVTIFdIRVJFIF হোস্টX05BTUU9JyIgKyBIb3N0TmFtZSArICInIik7CisgIHF1ZXJ5LmV4ZWMoIlNFTEVDVCBJRCwgUEFUSCwgR1JPVVBfTkFNRSwgQVVUT1RSSU1fTEVWRUwsIE5PUk1BTElaRV9MRVZFTCwgQ09ESU5HX0ZPUk1BVCBGUk9NIERST1BCT1hFUyBXSEVSRSBIT1NUX05BTUU9JyIgKyBIb3N0TmFtZSArICInIik7CiAgIAogICB3aGlsZShxdWVyeS5uZXh0KCkpIHsKICAgICBRU3RyaW5nIHBhdGggPSBxdWVyeS52YWx1ZSgxKS50b1N0cmluZygpOwogICAgIGludCBhdXRvdHJpbSA9IHF1ZXJ5LnZhbHVlKDMpLnRvSW50KCk7CiAgICAgaW50IG5vcm1hbGl6ZSA9IHF1ZXJ5LnZhbHVlKDQpLnRvSW50KCk7CisgICAgaW50IGNvZGluZ19mb3JtYXQgPSBxdWVyeS52YWx1ZSg1KS50b0ludCgpOwogCiAKQEAgLTY0NSw2ICs2NDYsMTEgQEAKICAgICBpZihub3JtYWxpemUgIT0gMCkgewogICAgICAgcG9zdC5hZGRWYXJpYWJsZSgiTk9STUFMSVpFX0xFVkVMIiwgUVN0cmluZzo6bnVtYmVyKG5vcm1hbGl6ZSkpOwogICAgIH0KKyAgICAKKyAgICBpZihjb2RpbmdfZm9ybWF0ID09IDAgfHwgY29kaW5nX2Zvcm1hdCA9PSAzKSB7CisgICAgICBwb3N0LmFkZFZhcmlhYmxlKCJGT1JNQVQiLCBRU3RyaW5nOjpudW1iZXIoY29kaW5nX2Zvcm1hdCkpOworICAgIH0=" | base64 -d > mp3_ingest.patch

    # Apply the patch using git apply
    git apply --ignore-whitespace mp3_ingest.patch
    mk-build-deps --install --remove --tool="apt-get -y" debian/control
    dpkg-buildpackage -us -uc -b
    
    cd ..
    sudo dpkg -i *.deb

    # 1. Ensure MySQL is running
sudo systemctl start mariadb

# 2. Extract password from current rd.conf (or use your build-time variable)
RD_DB_PASS=$(grep '^Password=' /etc/rd.conf | cut -d'=' -f2)

# 3. Replicate Installer Authentication & Permissions
echo "Applying database permissions..."
sudo mariadb -u root <<EOF
CREATE DATABASE IF NOT EXISTS Rivendell;
CREATE USER IF NOT EXISTS 'rduser'@'localhost' IDENTIFIED BY '$RD_DB_PASS';
GRANT ALL PRIVILEGES ON Rivendell.* TO 'rduser'@'localhost';
FLUSH PRIVILEGES;
EOF

# 4. Initialize Schema (Using source file from Git clone)
echo "Initializing database schema..."
sudo mariadb -u rduser -p"$RD_DB_PASS" Rivendell < /usr/local/src/rivendell-build/rivendell/schema/rivendell.sql

# 5. Register and start services
sudo systemctl daemon-reload
sudo systemctl enable rdcatchd rdairplay rdlogmanager || true
sudo systemctl start rdcatchd rdairplay rdlogmanager || true

    mark_step_completed "install_rivendell"
}

touch_pypad() {
    sudo mkdir -p /var/www/html
    sudo touch /var/www/html/meta.txt
    sudo chown -R pypad:pypad /var/www/html/meta.txt || true
    mark_step_completed "touch_pypad"
}

install_broadcasting_tools() {
    sudo apt-get -o Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y icecast2 jackd2 qjackctl liquidsoap vlc vlc-plugin-jack
    mark_step_completed "install_broadcasting_tools"
}

create_directories() {
    mkdir -p /home/rd/imports /home/rd/logs
    sudo chown -R rd:rd /home/rd/imports /home/rd/logs
    mark_step_completed "create_directories"
}

move_apps() {
    if [ -d "/home/rd/Rivendell-Cloud/APPS" ]; then
        mv /home/rd/Rivendell-Cloud/APPS /home/rd/imports/APPS
        chmod -R +x /home/rd/imports/APPS
        sudo chown -R rd:rd /home/rd/imports/APPS
    fi
    mark_step_completed "move_apps"
}

move_shortcuts() {
    mkdir -p /home/rd/Desktop
    if [ -d "/home/rd/imports/APPS/Shortcuts" ]; then
        mv /home/rd/imports/APPS/Shortcuts/* /home/rd/Desktop/ || true
    fi
    mark_step_completed "move_shortcuts"
}

move_custom_configs() {
    mkdir -p /home/rd/.config/vlc /home/rd/.config/rncbc.org
    if [ -d /home/rd/imports/APPS/configs ]; then
        cp -f /home/rd/imports/APPS/configs/vlc* /home/rd/.config/vlc/ || true
        cp -f /home/rd/imports/APPS/configs/QjackCtl.conf /home/rd/.config/rncbc.org/ || true
        cp -f /home/rd/imports/APPS/configs/.stereo_tool* /home/rd/ || true
    fi
    sudo chown -R rd:rd /home/rd/.config /home/rd/.stereo_tool* || true
    mark_step_completed "move_custom_configs"
}

fix_pypad_syntax() {
    PYTHON_FILE="/usr/lib/python3/dist-packages/rivendellaudio/pypad.py"
    if [ -f "$PYTHON_FILE" ]; then
        sudo sed -i "s/config\.readfp(open('\/etc\/rd\.conf'))/config.read('\/etc\/rd\.conf')/" "$PYTHON_FILE"
    fi
    mark_step_completed "fix_pypad_syntax"
}

# Execution Flow Orchestrator
if [ "$(whoami)" != "rd" ]; then
    ensure_tmp_step_dir
    system_update
    set_hostname
    create_rd_user
    copy_working_directory
    backup_bashrc
    configure_shell_profile
    touch "$INITIAL_STEPS_COMPLETED"
    sudo chown rd:rd "$INITIAL_STEPS_COMPLETED"
    echo "Phase 1 complete. Ready for build execution environment reboot."
    exit 0
fi

# Post-Reboot Initialization Run
ensure_rd_user
ensure_step_dir

if ! step_completed "install_tasksel"; then install_tasksel; fi
if ! step_completed "install_mate"; then install_mate; fi
if ! step_completed "install_xrdp"; then install_xrdp; fi
if ! step_completed "configure_xrdp"; then configure_xrdp; fi
if ! step_completed "set_mate_default"; then set_mate_default; fi

# --- CHANGE HERE: Bypass the Paravel installer function call ---
if ! step_completed "install_rivendell"; then install_rivendell; fi

if [[ "$INSTALL_TYPE" == "3" ]]; then
    if ! step_completed "disable_pulseaudio"; then disable_pulseaudio; fi
    if ! step_completed "fix_qt5"; then fix_qt5; fi
    if ! step_completed "enable_firewall"; then enable_firewall; fi
    if ! step_completed "harden_ssh"; then harden_ssh; fi
    if ! step_completed "restore_bashrc"; then restore_bashrc; fi
else
    if ! step_completed "touch_pypad"; then touch_pypad; fi
    if ! step_completed "install_broadcasting_tools"; then install_broadcasting_tools; fi
    if ! step_completed "create_directories"; then create_directories; fi
    if ! step_completed "move_apps"; then move_apps; fi
    if ! step_completed "move_shortcuts"; then move_shortcuts; fi
    if ! step_completed "move_custom_configs"; then move_custom_configs; fi
    if ! step_completed "configure_icecast"; then configure_icecast; fi
    if ! step_completed "enable_icecast"; then enable_icecast; fi
    if ! step_completed "disable_pulseaudio"; then disable_pulseaudio; fi
    if ! step_completed "fix_qt5"; then fix_qt5; fi
    if ! step_completed "extract_mysql_password"; then extract_mysql_password; fi
    if ! step_completed "update_backup_script"; then update_backup_script; fi
    if ! step_completed "import_sql_backup"; then import_sql_backup; fi
    if ! step_completed "fix_pypad_syntax"; then fix_pypad_syntax; fi
    if ! step_completed "enable_firewall"; then enable_firewall; fi
    if ! step_completed "harden_ssh"; then harden_ssh; fi
