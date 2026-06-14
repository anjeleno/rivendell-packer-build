# Changelog
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