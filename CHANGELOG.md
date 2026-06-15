# Changelog
## v0.27.1 - 2026-06-15
### Changes:
- **Fix `rivendell.pkr.hcl` final cleanup provisioner destroying the droplet before snapshotting**: the build log shows `Build Process Completed Successfully.` - `rivendell-auto-install.sh` (v0.27.0) ran end-to-end with no errors for the first time. Packer then errored with `/tmp/script_9800.sh: 4: history: not found`, exit 127, and destroyed the droplet without writing a snapshot.
- **Root cause**: `history -c` is a bash builtin. Packer's `shell` provisioner runs `inline` commands via `/bin/sh` (dash on Ubuntu), which has no `history` builtin - the command is "not found", exits 127, and Packer treats the whole build as failed.
- **Fix**: replaced `"history -c"` in the final cleanup provisioner with `"rm -f /root/.bash_history /home/rd/.bash_history"`, which achieves the same goal (no shell history baked into the golden image) using a command that works under `/bin/sh`.

## v0.27.0 - 2026-06-15
### Changes:
- **Decouple database import from the golden image build**: `import_sql_backup` was confirmed broken again - `RDDB_v430_Cloud.sql` is a v4.3.0 dump whose `DROPBOXES` table has neither `CREATE_GROUP` nor `CODING_FORMAT`, so the v0.26.7 `ALTER TABLE DROPBOXES ADD COLUMN IF NOT EXISTS CODING_FORMAT ... AFTER CREATE_GROUP` (run *before* `rddbmgr --modify`) fails with `ERROR 1054 (42S22): Unknown column 'CREATE_GROUP' in 'DROPBOXES'` and kills the build under `set -e`, ~1h40m into every run.
- **Root cause**: this step doesn't belong in the Packer build at all. The golden image already finishes `install_rivendell` with a working, vanilla v4.4.1 schema from `rddbmgr --create` - swapping that database out from under freshly-started daemons mid-build (and hand-patching a v4.3.0 dump's columns to match a moving-target v4.4.1 schema) is exactly the kind of "golden image vs. data" coupling that the v0.26.0 source-patch split already avoided for `mp3_ingest.patch`.
- **Fix**: removed `import_sql_backup` entirely from `rivendell-auto-install.sh` (and its call in the Phase 2 flow). All other custom-config steps (`touch_pypad` through `harden_ssh`, including `move_apps`/`move_custom_configs`/`update_backup_script`) are confirmed landing successfully on every run and are unchanged. Added `APPS/rivendell-data-ingest.sh`, a standalone one-time script (shipped to `/home/rd/imports/APPS/` via the existing `move_apps` step) that the user runs manually over SSH after first boot: stops `rivendell`/`apache2`, drops/recreates the `Rivendell` database, imports `RDDB_v430_Cloud.sql`, then runs `sudo rddbmgr --modify` (with no manual `ALTER TABLE`, since `--modify`'s own v4.3.0→v4.4.1 migration path adds `CREATE_GROUP`/`CODING_FORMAT` itself) and restarts the services. `extract_mysql_password` stays in the golden image, since `update_backup_script` still depends on it.

## v0.26.11 - 2026-06-15
### Changes:
- **Remove stale `groupadd -g 514 rivendell` calls**: cloned the actual v4.4.1 tag and compared `debian/postinst` against this script. The real package creates the `rivendell` group/user with **GID/UID 150** itself during `dpkg -i`/`apt-get -f` (step 5) and uses it to own `/var/snd`, `/var/log/rivendell`, etc. Our script pre-created the group with **GID 514** (twice, under a "Replicate Paravel group/permissions" comment - a leftover from the old Paravel-apt-repo install path), which caused the postinst's own `groupadd -g 150` to silently fail and left the `rivendell` system user in GID 514 instead of 150.
- **Fix**: removed both `groupadd -g 514 rivendell` calls. `chown rd:rivendell /etc/rd.conf` (step 0, which ran before the group existed either way) changed to `chown rd:rd` - mode 644 is what actually makes the file readable. Moved `usermod -aG rivendell rd` to after step 5 (`apt-get install -f -y`), once the package's own postinst has created the `rivendell` group (GID 150) for `rd` to join.
- **Remove no-op `systemctl enable/start rdcatchd rdairplay rdlogmanager`**: confirmed via the upstream `systemd/` directory that Rivendell ships exactly one unit, `rivendell.service` (`ExecStart=/usr/sbin/rdservice`). `rdservice` spawns `rdcatchd`/`rdairplay`/`rdlogmanager` itself as child processes based on the `STATIONS`/`SERVICES` rows for this host - there are no corresponding `.service` units, so these `systemctl ... || true` calls (in `install_rivendell` step 7 and the v0.26.10 `import_sql_backup` restart) silently failed and did nothing. Removed; `systemctl restart rivendell` is what actually matters.

## v0.26.10 - 2026-06-15
### Changes:
- **Fix daemons left running against a database `import_sql_backup` is about to destroy**: `install_rivendell` step 8 starts `rivendell`, `apache2`, `rdcatchd`, `rdairplay`, and `rdlogmanager` against the schema `rddbmgr --create` just built. `import_sql_backup` then immediately `DROP DATABASE`/`CREATE DATABASE`/reimports/`rddbmgr --modify`s that same database while those daemons are still connected.
- **Root cause**: Rivendell's schema is `ENGINE=MyISAM` (table-level locking). A `DROP DATABASE` while connected daemons hold table locks can hang the build indefinitely, and even if it doesn't, a snapshot taken with those daemons pointed at a since-replaced DB would boot into the golden image in a crashed/stale state.
- **Fix**: in `import_sql_backup`, `sudo systemctl stop` the affected services before the `DROP DATABASE`/reimport/`rddbmgr --modify` sequence, then restart them afterward (mirroring step 8's own `systemctl restart rivendell apache2` / `systemctl start rdcatchd rdairplay rdlogmanager` pattern).
- **Fix idempotency bug in `extract_mysql_password`**: it was gated behind `step_completed`, but only sets the in-memory `$MYSQL_PASSWORD` variable with no persisted side effect. If its step marker existed from a prior partial run (e.g. a manual rerun on a held-open droplet) while `import_sql_backup` hadn't completed yet, `$MYSQL_PASSWORD` would be empty in the new process and break the DB import's password. Now called unconditionally every run.
- **Remove stale comment**: deleted the orphaned `# --- CHANGE HERE: Bypass the Paravel installer function call ---` comment above the `install_rivendell` step - that bypass logic already lives inside `install_rivendell` itself per its own header description.

## v0.26.9 - 2026-06-15
### Changes:
- **Fix `import_sql_backup` failure**: `ERROR 1698 (28000): Access denied for user 'root'@'localhost'` at the start of `import_sql_backup`, ~1h39m into the build (everything before it, including `install_rivendell`, now completes successfully).
- **Root cause**: this step runs as the `rd` Linux user. The v0.26.7 fix called `mariadb -h "$DB_HOST" -u root -e "DROP DATABASE ..."` directly, but MariaDB's `root@localhost` account uses `unix_socket` auth, which only authenticates when the connecting *OS* user is `root`. Step 7's equivalent command already runs via `sudo mariadb -u root <<EOF`; this one didn't match that pattern.
- **Fix**: prefix the command with `sudo` (and drop the `-h "$DB_HOST"` TCP host flag) so it authenticates via the root unix socket, matching step 7.

## v0.26.8 - 2026-06-15
### Changes:
- **Prevent MATE desktop bloat at install time instead of cleaning it up afterward**: `install_mate` previously installed `ubuntu-mate-desktop`, whose `Recommends` pull in LibreOffice (Writer/Calc/Impress), Evolution, Rhythmbox, Shotwell, Firefox, Transmission, and more - all of which had to be removed in a separate post-install cleanup pass, slowing down the build.
- **Fix**: swap `ubuntu-mate-desktop` for `ubuntu-mate-core` (the same package `-desktop` depends on, minus the bloat-laden `Recommends`) and add `--no-install-recommends`. `ubuntu-mate-core`'s hard `Depends` already include `mate-session-manager`, `marco`, `xorg`, `caja`, and `mate-terminal`, so the existing XRDP + `mate-session` setup (`configure_xrdp`, `set_mate_default`) is unaffected.

## v0.26.7 - 2026-06-15
### Changes:
- **Fix `install_rivendell` step 7 failure**: `sudo rddbmgr --modify` (added in v0.26.6) failed with `rddbmgr: unable to determine DB schema, aborting` and killed the build via `set -e`, immediately after `CREATE DATABASE IF NOT EXISTS Rivendell` - all 5 `.deb` packages installed and configured successfully, but the database step never got further.
- **Root cause**: `--modify` upgrades an *existing* schema to the current version. The database was just created and is completely empty, so `rddbmgr` has no schema version to read and aborts instead of building one.
- **Fix**: use `sudo rddbmgr --create` to build the v4.4.1 schema from scratch in the empty database.
- **Fix invalid SQL in `import_sql_backup`**: `DROP TABLE IF EXISTS \`*\`;` is not valid MariaDB syntax (`*` isn't a wildcard for table names). Replaced with `DROP DATABASE IF EXISTS Rivendell; CREATE DATABASE Rivendell; GRANT ...` to cleanly wipe the `rddbmgr --create` schema before importing the `RDDB_v430_Cloud.sql` payload.
- **Fix missing post-import schema upgrade**: importing the v4.3.0 SQL payload reverts the schema to v4.3.0, which the installed v4.4.1 daemons can't use. Added `sudo rddbmgr --modify` immediately after the import to upgrade the imported schema to v4.4.1.
- **Fix script-ending syntax error**: the final `if [[ "$INSTALL_TYPE" == "3" ]]; then ... else ... ` block (introduced in v0.23.0) was missing its closing `fi`, making the script fail `bash -n`. This wasn't hit by prior builds because they always aborted earlier in `install_rivendell`, but would have broken any build that got past step 7. Added the closing `fi` and a final `echo "Build Process Completed Successfully."`.

## v0.26.6 - 2026-06-14
### Changes:
- **Fix `install_rivendell` step 7 failure**: `mariadb -u rduser ... Rivendell < .../schema/rivendell.sql` failed with "No such file or directory" - all 5 `.deb` packages installed and configured successfully (v0.26.5 fix confirmed working!), but the database step still referenced a static `schema/rivendell.sql` dump that no longer exists in v4.4.1.
- **Root cause**: v4.4.1 builds/upgrades the database schema programmatically via `rddbmgr` (see `utils/rddbmgr/updateschema.cpp`), not a static SQL dump. The `rivendell` package's `postinst` already calls `rddbmgr --modify` automatically, but at that point in `dpkg -i`/`apt-get -f`, MariaDB isn't running yet and the `rduser`/`Rivendell` DB don't exist yet, so it fails with "Access denied for user 'rduser'@'localhost'" (visible in the log, non-fatal to the package install).
- **Fix**: after creating the `Rivendell` database and `rduser` MySQL user, run `sudo rddbmgr --modify` to build the schema (re-running what postinst already attempted, now that the DB exists). Also added `sudo systemctl restart rivendell apache2` in step 8 to restart the services that started without a working DB during postinst.

## v0.26.5 - 2026-06-14
### Changes:
- **Fix `dpkg -i *.deb` failure ("dependency problems prevent configuration")**: `dpkg-buildpackage` itself now completes successfully (confirms the v0.26.4 `DOCBOOK_STYLESHEETS` fix worked - the build got through `docs/stylesheets` and produced all `.deb` packages). The final `sudo dpkg -i *.deb` step then failed because `dpkg -i` doesn't resolve dependencies: `rivendell`, `rivendell-dev`, `rivendell-importers`, `rivendell-select`, and `rivendell-webget` were left unconfigured, missing `python3-mysqldb`, `icedax`, and `qt5-style-plugins`.
- **Fix**: `dpkg -i *.deb || true` followed by `sudo apt-get install -f -y`, the standard pattern for installing local `.deb`s with apt-resolved dependencies - `apt-get -f` pulls in the three missing packages and finishes configuring everything `dpkg -i` left unconfigured.

## v0.26.4 - 2026-06-13
### Changes:
- **Fix `dpkg-buildpackage` failure during `docs/stylesheets` build**: `xsltproc -o book-fo-titlepages.xsl ../../helpers/docbook/template/titlepage.xsl ...` failed with "cannot parse ../../helpers/docbook/template/titlepage.xsl" (`make: *** [debian/rules:7: build] Error 2`), aborting the entire build after everything else (lib, all apps, apis, tests) compiled successfully.
- **Root cause**: `configure.ac` only creates the `helpers/docbook` symlink to the system docbook-xsl stylesheets (which provides `template/titlepage.xsl`) if the `$DOCBOOK_STYLESHEETS` env var is set. We installed `docbook-xsl-ns` in v0.26.2 but never exported the variable.
- **Fix**: export `DOCBOOK_STYLESHEETS=/usr/share/xml/docbook/stylesheet/docbook-xsl-ns` (per Rivendell's `INSTALL` doc, Ubuntu 24.04 LTS section) before `dpkg-buildpackage -us -uc -b`.

## v0.26.3 - 2026-06-13
### Changes:
- **Fix `mk-build-deps: dpkg --unpack failed` / "requested operation requires superuser privilege"**: `install_rivendell` runs as the unprivileged `rd` user (phase 2). `mk-build-deps --install ... debian/control` successfully built the `rivendell-build-deps` dummy package, but then failed while trying to `dpkg --unpack` it without root.
- **Added `sudo` to the `mk-build-deps` invocation** so it can install the generated build-dependencies package (and pull in `apt-get`-resolved deps via `--tool="apt-get -y"`).

## v0.26.2 - 2026-06-12
### Changes:
- **Fix `autoconf` failure (`possibly undefined macro: AC_MSG_ERROR`)**: caused by a missing `pkg-config` (no `pkg.m4`), so `aclocal` couldn't resolve `PKG_CHECK_MODULES` in `configure.ac:96`, leaving the embedded `AC_MSG_ERROR` unexpanded.
- **Replaced the minimal system dependency list with Rivendell's documented Ubuntu 24.04 LTS build dependencies** (from the project's own `INSTALL` file): Qt5 dev headers, JACK/ALSA/FLAC/taglib/libsamplerate/MusicBrainz/SoundTouch/ImageMagick dev packages, `pkg-config`, `autoconf-archive`, etc. Omitted `hpklinux-dev` (requires Paravel's private apt repo; `configure.ac` already handles its absence gracefully).

## v0.26.1 - 2026-06-12
### Changes:
- **Fix `install_rivendell` build failure**: A fresh v4.4.1 checkout ships `debian/control.src` (a template), not `debian/control`. `mk-build-deps debian/control` was therefore failing with `E: You must put some 'deb-src' URIs in your sources.list` because it fell back to treating the path as an apt package name.
- **Added `./autogen.sh` step**: Runs immediately after `git checkout` and before `mk-build-deps`. This generates `debian/control`, `debian/rules`, `debian/changelog` from their `.src` templates and produces the `configure` script via autotools, matching Rivendell's own `configure_build.sh` process.

## v0.26.0 - 2026-06-12
### Changes:
- **Vanilla Golden Image Build**: Removed the in-build `mp3_ingest.patch` injection from `install_rivendell`. The build now compiles and installs stock, unpatched Rivendell v4.4.1 from source.
- **Patch Layering Strategy**: Custom patches (e.g. `mp3_ingest.patch`) will be applied as a separate stage on top of this golden image, rather than baked into the source build. This decouples base-image stability from patch development/iteration.
- **Snapshot Naming**: Updated Packer snapshot name to `rivendell-4.4.1-vanilla-{{timestamp}}` to reflect the unpatched base image.

## v0.25.0 - 2026-06-10
### Changes:
- **Dual-Architecture Golden Image Build**: Automatically detects architecture (AMD64 vs ARM64).
- **ARM64 Scaffolding Support**: Bypasses Paravel repository limitations on ARM64 by manually scaffolding Apache and MariaDB environments prior to local source compilation.
- **Robust Out-of-the-Box Ingest**: Exposes client-side `--audio-format` flag for `rdimport` and custom dropdown options for Rivendell Dropboxes.
- **Reliable Patch Delivery**: Downloads and applies the exact `mp3_ingest.patch` directly from GitHub to resolve encoding, newline, and base64 parsing issues.
- **Unattended execution support**: Upgraded script to execute completely non-interactively for server builds and Packer automation.

## v0.23.4 - 2025-04-01
### Changes:
- **The script now detects Ubuntu 24.04 and invokes the appropriate Rivendell installer for Noble.
- **Introduced conditional logic to execute specific steps based on the user's choice of installation type
- **Refactored Script into Pre-Rivendell and Post-Rivendell Sections
- **Revised radio.liq (liquidsoap config) for comaptibility with Ubuntu 24.04
#
## v0.23.2 - 2025-04-01
### Changes:
- **Escaped quotes in the sed commnad relating to fixing deprecated ConfigParser config.readfp() with config.read() for compatibility with Python 3.9+ on Ubuntu 24.04 installs
#
## v0.23.1 - 2025-04-01
### Changes:
- **Replaced deprecated ConfigParser config.readfp() with config.read() for compatibility with Python 3.9+ on Ubuntu 24.04 installs
#
## v0.23.0 - 2025-04-01
### Changes:
- **Added check to see which version of Ubuntu is installed and invoke Rivendell installer for correct version.
# Changelog
## v0.21.1 - 2025-03-20
### Changes:
- **Added multiple choice for Rivendell insatallation type.
- **Fixed issue with UFW causing the script fail if you're working in a local VM and only plug in your local subnet without an WAN IP.
#
## v0.21.0 - 2025-03-18
### Changes:
- **Fully automated installation and configuration of Rivendell, with advanced
- **features optimized for Ubuntu 22.04 on a cloud VPS. It includes everything you need
- **out-of-the-box to stream with Jack, liquidsoap, icecast and audio processing.
#
## v0.20.58 - 2025-03-17
### Changes:
- **Placed shortcut on deskto to add cronjobs to crontab. 
- **Cleaned up script comments
#
## v0.20.57 - 2025-03-17
### Changes:
- **autologgen injects into crtontab but sql nightly backup fails. Splitting them into separate functions to see if that works. Super annoying.
#
## v0.20.56 - 2025-03-17
### Changes:
- **Resolving last issue: injecting nightly backup script into crontab.🤔
- **Changed sql backup path from /APPS/.sql to /APPS/sql. Fingers crossed. 
#
## v0.20.54 - 2025-03-17
### Changes:
- **Resolving last issue: injecting nightly backup script into crontab.
- **Added housekeeping to remove installation files. 
#
## v0.20.53 - 2025-03-17
### Changes:
- **Removed duplicate and conflicting entries in script.
- **Resolved creating meta.txt
#
## v0.20.51 - 2025-03-17
### Changes:
- **Dropping default Rivendell tables and importing custom sql with advanced featues implemented
- **Debugging the sql nightly backup injection in crontab
- **Fixed vlcrc config getting moved
- **Debugging meta.txt creation.
#
## v0.20.50 - 2025-03-17
### Changes:
- **Housekeeping.
- **Fixing the sql nightly backup injection in crontab
- **vlcc config wasn't getting moved. Added debugging and fixing.
- **meta.txt isn't getting created. Added debugging and fixing.
#
## v0.20.48 - 2025-03-16
### Changes:
- **Tons of fixes. Adding custom liquidsoap, icecast, stereotool, vlc configs pullling all the magic together. 
#
## v0.20.31 - 2025-03-16
### Changes:
- **Working on logic. Still...
#
## v0.20.16 - 2025-03-16
### Changes:
- **Refining...
#
## v0.20.13 - 2025-03-16
### Changes:
- **Almost there... Still working out some kinks.
#
## v0.20.2 - 2025-03-15
### Changes:
- **Refining logic.
#
## v0.20.1 - 2025-03-15
### Changes:
- **Keep first run logic, combine new features, rinse and repeat.
#
## v0.20.0 - 2025-03-15
### Changes:
- **Logic overhaul.
#
## v0.19.9 - 2025-03-15
### Changes:
- **Debugging.
#
## v0.19.8 - 2025-03-15
### Changes:
- **Combining first-run logic from v0.19.0 with improvmements in step-tracking in v0.19.7.
#
## v0.19.7 - 2025-03-15
### Changes:
- **Fixing logic.
#
## v0.19.6 - 2025-03-15
### Changes:
- **Troubleshhoting (and hopefully fixing) logic.
- **Renamed root directory and script (lowercase "R," because switching manually sucks lol)
#
## v0.19.5 - 2025-03-15
### Changes:
- **Fixed issue where step tracking directory was created before the 'rd' user existed.
- **Ensured working directory is copied after the 'rd' user is created.
- **Improved flow and debugging output.
#
## v0.19.3 - 2025-03-15
### Changes:
- **Fixed issues with copying the working directory and configuring .bashrc.
- **Ensured the script enforces the 'rd' user check after reboot.
- **Added explicit error handling for critical steps.
#
## v0.19.1 - 2025-03-15
### Changes:
- **Fixed duplicate function definitions.
- **Reordered steps to ensure 'rd' user is created before enforcing the 'rd' user check.
- **Moved 'hostname_timezone' to run only after reboot.
- **Prevented 'copy_working_directory' from running twice.
- **Updated version number in header.
#
## v0.19.0 - 2025-03-15
### Changes:
- **Added backup and restore functionality for .bashrc.
- **Improved SQL password handling for database operations.
- **Updated Icecast configuration.
- **Added error handling for SQL operations.
- **Integrated optional privilege management for rduser.
- **Improved readability and added comments for clarity.
#
## v0.18.0 - 2025-03-14
### Changes:
- **Initial release of the script.
- **Includes installation of Rivendell, MATE Desktop, xRDP, and broadcasting tools.
- **Added step tracking to avoid re-running completed steps.
- **Configured Icecast, Liquidsoap, and other broadcasting tools.
#
## v0.18.0 - 2025-03-14
### Changes:
- **RRebased on v0.12.x codebase with critical fixes
- **RFixed Icecast configuration to use custom icecast.xml
- **RAdded check to ensure Desktop directory exists before moving shortcuts
- **RCorrected MySQL password extraction and injection in backup script
- **RResolved Icecast permissions issues
#
## v0.17.3 (2025-03-14)
### Changes:
- **Fixed**: Improved step tracking mechanism to ensure completed steps are respected after reboots.
- **RAdded ownership checks for the step tracking directory (`/home/rd/rivendell_install_steps`) to ensure it is always owned by the `rd` user.
- **REnhanced step completion checks to prevent re-execution of already completed steps (e.g., MATE Desktop installation).
- **Improved**: Graceful handling of mid-script reboots to ensure the script resumes correctly.
- **Updated**: Documentation and prompts for better user guidance during installation.
- **Tested**: Verified on a fresh Ubuntu installation to ensure smooth execution after reboots.
#
## v0.17.1 (2025-03-14)
### Changes:
- **RAdded mid-script reboot handling to allow reboots after installing MATE Desktop and xRDP.
- **RIntroduced the `mid_script_reboot` function to mark steps as completed and prompt for a reboot.
- **Rpdated step tracking to ensure the script can resume after reboots.
- **RImproved robustness by checking for existing installations (e.g., MATE Desktop).
- **RAdded debugging output for easier troubleshooting.
- **RUpdated documentation and comments for clarity.
#
## v0.17 (2025-03-14)
### Changes:
- **RFix step tracking and basic installation flow.
- **RTroubleshoot logic
#
## v0.16 - 2025-03-13
### Changes:
- **RFixed interactive prompts breaking by replacing global log redirection with selective logging.
- **RAdded a `log` function to log non-interactive output while preserving interactive prompts.
- **RUpdated log file handling to ensure proper permissions and ownership.
- ** # - Removed `exec > >(tee -a "$TEMP_LOG_FILE") 2>&1` to prevent interference with interactive prompts.
#
## v0.15 - 2025-03-13
### Changes:
- **Interactive terminal check**: Added a check to ensure the script runs in an interactive terminal.
- **Locale settings**: Set locale to UTF-8 to prevent display issues.
- **Fixed log file creation**: Used a temporary file in `/tmp` before moving it to `/home/rd` after the `rd` user is created.
- **Restored interactive timezone configuration**: Reverted to the interactive timezone picker for ease of use.
- **Escaped `$` characters in Icecast passwords**: Fixed password formatting in `icecast.xml`.
- **SSH hardening**: Disabled password authentication in both `/etc/ssh/sshd_config` and `/etc/ssh/sshd_config.d/50-cloud-init.conf`.
- **Renamed `Desktop Shortcuts` to `Shortcuts`**: Updated paths to reflect the renamed folder.
- **Added RDP login note**: Prompted the user to log in via RDP before moving shortcuts.
- **Improved `rd` user creation**: Added a password prompt and ensured correct permissions for the home directory.
#
## v0.14 - 2025-03-13
### Changes:
- **Fixed log file creation**: Used a temporary file in `/tmp` before moving it to `/home/rd` after the `rd` user is created.
- **Restored interactive timezone configuration**: Reverted to the interactive timezone picker for ease of use.
- **Escaped `$` characters in Icecast passwords**: Fixed password formatting in `icecast.xml`.
- **SSH hardening**: Disabled password authentication in both `/etc/ssh/sshd_config` and `/etc/ssh/sshd_config.d/50-cloud-init.conf`.
- **Renamed `Desktop Shortcuts` to `Shortcuts`**: Updated paths to reflect the renamed folder.
- **Added RDP login note**: Prompted the user to log in via RDP before moving shortcuts.
- **Improved `rd` user creation**: Added a password prompt and ensured correct permissions for the home directory.