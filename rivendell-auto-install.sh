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
    UBUNTU_VERSION=$(lsb_release -rs)
    SYS_ARCH=$(uname -m)

    echo "Executing Rivendell Core Target Pipeline..."
    echo "Detected Architecture: $SYS_ARCH | OS Version: $UBUNTU_VERSION"

    # FIX: Shift execution context to a globally readable directory to bypass 
    # 'pathconf: Permission denied' errors during privilege drops in Packer.
    # Placing this above the architecture check covers both AMD64 and ARM64 automatically.
    cd /tmp || exit 1

    # --- ARCHITECTURE SWAP ROUTINE ---
    if [[ "$SYS_ARCH" == "x86_64" ]]; then
        echo "Executing Production AMD64 Path (Using Paravel Base Script Installer)..."
        wget -q https://software.paravelsystems.com/ubuntu/dists/noble/main/install_rivendell.sh
        chmod +x install_rivendell.sh
        # 1. Force APT to ignore "Recommended" bloatware globally for this build
        echo 'APT::Install-Recommends "false";' | sudo tee /etc/apt/apt.conf.d/99no-recommends
        
        # 2. Rewrite Paravel's script to install the minimal MATE core instead of the bloated desktop
        sed -i 's/ubuntu-mate-desktop/ubuntu-mate-core/g' install_rivendell.sh
        sed -i 's/libreoffice//g' install_rivendell.sh
        # Run non-interactively passing default option
        # Use an explicit heredoc to guarantee non-interactive stdin mapping to prevent pathconf errors
        sudo DEBIAN_FRONTEND=noninteractive ./install_rivendell.sh <<INST
$INSTALL_TYPE
INST

        # FIX: The Paravel script pulls down heavy desktop packages. 
        # Purge them immediately after the installer finishes to shrink the Golden Image.
        echo "Purging unnecessary desktop bloatware..."
        sudo apt-get purge -y libreoffice* evolution* transmission* rhythmbox* celluloid* hexchat*
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

    # --- SOURCE BUILD & PATCH INTERCEPT (RUNS UNIVERSALLY) ---
    echo "Beginning source tree interception & compilation..."
    sudo apt-get -o Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y git devscripts equivs dpkg-dev

    # FIX: Paravel has not published the 'deb-src' (source code) repo for Noble (24.04) yet.
    # We will dynamically copy their APT configuration, convert it to 'deb-src', and point
    # it to their Jammy (22.04) distribution which definitely contains the 'debian/' folder.
    PARAVEL_LIST=$(grep -rl "software.paravelsystems.com" /etc/apt/sources.list.d/ | head -n 1)
    if [ -n "$PARAVEL_LIST" ]; then
        grep "^deb " "$PARAVEL_LIST" | sed 's/^deb /deb-src /' | sed 's/noble/jammy/g' | sudo tee /etc/apt/sources.list.d/paravel-jammy-src.list
    fi
    
    sudo apt-get update

    # Pull the source from APT (which includes the 'debian/' folder) instead of GitHub
    sudo mkdir -p /usr/local/src/rivendell-build
    sudo chmod 777 /usr/local/src/rivendell-build
    cd /usr/local/src/rivendell-build
    
    sudo apt-get source rivendell
    cd rivendell-*/

    # Inject the unified MP3 patch
    sudo tee mp3_ingest.patch > /dev/null << 'EOF'
--- a/schema/rivendell.sql
+++ b/schema/rivendell.sql
@@ -450,6 +450,7 @@
   DESTINATION varchar(255) default NULL,
   CUT_CREATION tinyint(4) NOT NULL default '0',
   CREATE_GROUP varchar(64) default NULL,
+  CODING_FORMAT int(11) NOT NULL default '-1',
   AUTOTRIM_LEVEL int(11) NOT NULL default '0',
   NORMALIZE_LEVEL int(11) NOT NULL default '0',
   PRIMARY KEY  (ID)
 
--- a/utils/rdimport/rdimport.cpp
+++ b/utils/rdimport/rdimport.cpp
@@ -105,6 +105,7 @@
   printf("  --metadata-pattern=<pattern>\n");
   printf("  --autotrim-level=<level>\n");
   printf("  --normalization-level=<level>\n");
+  printf("  --audio-format=<0|3> (0=PCM16, 3=MPEG Layer III)\n");
   printf("  --use-high-cart\n");
   printf("  --use-low-cart\n");
 }
@@ -140,6 +141,7 @@
   int metadata_offset=0;
   int autotrim_level=0;
   int normalize_level=0;
+  int audio_format=-1;
   bool use_high_cart=false;
   bool use_low_cart=false;
   bool delete_source=false;
@@ -215,6 +217,9 @@
     } else if(strncmp(argv[i],"--normalization-level=",22)==0) {
       normalize_level=atoi(&argv[i][22]);
 
+    } else if(strncmp(argv[i],"--audio-format=",15)==0) {
+      audio_format=atoi(&argv[i][15]);
+
     } else if(strncmp(argv[i],"--use-high-cart",15)==0) {
       use_high_cart=true;
 
@@ -345,6 +350,11 @@
     post.addVariable("NORMALIZE_LEVEL",QString::number(normalize_level));
   }
 
+  // Append the custom format flag if explicitly set by the user
+  if(audio_format == 0 || audio_format == 3) {
+    post.addVariable("FORMAT",QString::number(audio_format));
+  }
+
   if(use_high_cart) {
     post.addVariable("USE_HIGH_CART","1");
   }

--- a/web/rdxport/rdxport.cpp
+++ b/web/rdxport/rdxport.cpp
@@ -485,12 +485,24 @@
     return;
   }
 
-  // Default to the Host's globally configured Audio Format
+  // Fetch the Host's globally configured Audio Format
   int targetFormat = hostQuery.value(0).toInt();
 
+  // INTERCEPT: Check if the client explicitly requested a specific codec format
+  if(cgiHasParam("FORMAT")) {
+    int requestedFormat = cgiParamAsInt("FORMAT");
+    if(requestedFormat == 0 || requestedFormat == 3) {
+      targetFormat = requestedFormat;
+      syslog(LOG_INFO, "rdxport: Host format overridden. Using explicit format %d", targetFormat);
+    }
+  }
+
   // Proceed with the standard transcoding assignment using targetFormat
   RDXportTranscoder transcoder;
   transcoder.setFormat(targetFormat);

--- a/daemons/rdcatchd/rdcatchd.cpp
+++ b/daemons/rdcatchd/rdcatchd.cpp
@@ -620,7 +620,7 @@
 void RDCatch::ProcessDropboxes()
 {
   QSqlQuery query;
-  query.exec("SELECT ID, PATH, GROUP_NAME, AUTOTRIM_LEVEL, NORMALIZE_LEVEL FROM DROPBOXES WHERE HOST_NAME='" + HostName + "'");
+  query.exec("SELECT ID, PATH, GROUP_NAME, AUTOTRIM_LEVEL, NORMALIZE_LEVEL, CODING_FORMAT FROM DROPBOXES WHERE HOST_NAME='" + HostName + "'");
   
   while(query.next()) {
     QString path = query.value(1).toString();
@@ -628,6 +628,7 @@
     int autotrim = query.value(3).toInt();
     int normalize = query.value(4).toInt();
+    int coding_format = query.value(5).toInt();
 
@@ -645,6 +646,11 @@
     if(normalize != 0) {
       post.addVariable("NORMALIZE_LEVEL", QString::number(normalize));
     }
+    
+    if(coding_format == 0 || coding_format == 3) {
+      post.addVariable("FORMAT", QString::number(coding_format));
+    }
EOF

    sudo patch -p1 --fuzz=3 < mp3_ingest.patch || true

    echo "Resolving source dependency mapping for host architecture..."
    
    # FIX: DigitalOcean disables source repos by default. 
    # Enable 'deb-src' so mk-build-deps can map build dependencies.
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
        sudo sed -i 's/Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
    fi
    if [ -f /etc/apt/sources.list ]; then
        sudo sed -i 's/^# deb-src/deb-src/' /etc/apt/sources.list
    fi
    sudo apt-get update

    # Now execute the dependency build
    sudo mk-build-deps -i -r -t "apt-get -y --no-install-recommends" debian/control

    echo "Compiling architecture-native application packages..." 
    sudo dpkg-buildpackage -us -uc -b

    echo "Deploying newly-built target application suite..."
    cd ..
    sudo dpkg -i rivendell_*.deb rivendell-server_*.deb || sudo apt-get -o Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -f -y

    sudo systemctl daemon-reload || true
    sudo systemctl restart rdcatchd || true

    cd /home/rd/Rivendell-Cloud
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
