#!/bin/bash
# Rivendell Post-Deploy Database Ingestion Script
# Version: 1.0.0
# Date: 2026-06-15
# Description: Imports the production v4.3.0 database dump (RDDB_v430_Cloud.sql)
#              into a droplet built from the vanilla Rivendell v4.4.1 golden
#              image, then upgrades the schema to v4.4.1 via `rddbmgr --modify`.
#
#              This is a ONE-TIME, manual step - run it over SSH after the
#              droplet's first boot. It is intentionally NOT part of the
#              Packer build: the golden image already has a working blank
#              v4.4.1 schema from `rddbmgr --create`, and running this during
#              the build would mean tearing the database out from under
#              freshly-started daemons inside a fragile multi-hour build.
#
# Usage: /home/rd/imports/APPS/rivendell-data-ingest.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_FILE="$SCRIPT_DIR/RDDB_v430_Cloud.sql"

DB_HOST="localhost"
DB_USER="rduser"
DB_NAME="Rivendell"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Database backup not found at $BACKUP_FILE. Aborting."
    exit 1
fi

echo "Extracting MySQL password from /etc/rd.conf..."
MYSQL_PASSWORD=$(awk -F= '/\[mySQL\]/{flag=1;next}/\[/{flag=0}flag && /Password=/{print $2;exit}' /etc/rd.conf)
if [ -z "$MYSQL_PASSWORD" ]; then
    MYSQL_PASSWORD="rduser"
fi
DB_PASS="$MYSQL_PASSWORD"

echo "Stopping Rivendell services..."
# rdcatchd/rdairplay/rdlogmanager are spawned by rdservice itself, not
# separate units - stopping/restarting rivendell covers them.
sudo systemctl stop rivendell apache2 || true

echo "Recreating database..."
# sudo (not -h/-u root over TCP): root@localhost uses unix_socket auth,
# which only authenticates when the connecting OS user is actually root.
sudo mariadb -u root -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; CREATE DATABASE \`$DB_NAME\`; GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"

echo "Importing $BACKUP_FILE..."
mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$BACKUP_FILE"

# The imported dump is a v4.3.0 schema; rddbmgr --modify walks it through
# every versioned migration step up to v4.4.1 (adding DROPBOXES.CREATE_GROUP,
# DROPBOXES.CODING_FORMAT, etc. itself), so no manual ALTER TABLE is needed
# or safe here.
echo "Upgrading imported database schema (v4.3.0) to v4.4.1..."
sudo rddbmgr --modify

echo "Restarting Rivendell services..."
sudo systemctl restart rivendell apache2

echo "Database ingestion complete."
