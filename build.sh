#!/usr/bin/env bash
# build.sh - Build automated Arch Linux ISO for Dell Venue 8 Pro 5830
# This script clones the upstream hardware fixes from ramonvanraaij/dell-venue-8-pro
# and integrates them into a temporary archiso tree before building.

set -o errexit -o nounset -o pipefail

# Resolve the home directory of the user who invoked sudo (or the current user
# if run directly), so the ISO lands in their home rather than /root.
REAL_USER="${SUDO_USER:-${USER}}"
REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
REAL_GROUP="$(id -gn "${REAL_USER}")"

OUTPUT_DIR="${1:-${REAL_HOME}/archiso-out}"
WORK_DIR="${2:-${REAL_HOME}/archiso-work}"
TEMP_DIR="$(mktemp -d)"
UPSTREAM_REPO="https://github.com/ramonvanraaij/dell-venue-8-pro.git"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ARCHISO_DIR="${SCRIPT_DIR}/archiso"
BUILD_ARCHISO_DIR="${TEMP_DIR}/archiso"
AIROOTFS="${BUILD_ARCHISO_DIR}/airootfs"

log() { echo "[BUILD] $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

trap 'rm -rf "${TEMP_DIR}"' EXIT

log "Automated Arch Linux ISO builder for Dell Venue 8 Pro 5830"
log "Output directory : ${OUTPUT_DIR}"
log "Work directory   : ${WORK_DIR}"
log "Source archiso   : ${SOURCE_ARCHISO_DIR}"
log "Build archiso    : ${BUILD_ARCHISO_DIR}"

# === Step 0: Prepare isolated build tree ===
log "Copying archiso profile into temporary build tree..."
cp -a "${SOURCE_ARCHISO_DIR}" "${BUILD_ARCHISO_DIR}"

# === Step 1: Clone upstream repository ===
log "Cloning upstream hardware fixes from ramonvanraaij/dell-venue-8-pro..."
git clone --depth=1 "${UPSTREAM_REPO}" "${TEMP_DIR}/upstream" 2>&1 | grep -E '(Cloning|Receiving|Resolving|done)' || true

if [ ! -d "${TEMP_DIR}/upstream" ]; then
    error "Failed to clone upstream repository. Check network connectivity."
fi

log "Upstream repository cloned successfully."

# === Step 2: Copy hardware fix configurations into temporary build tree ===
log "Integrating hardware fixes into temporary archiso tree..."

mkdir -p \
  "${AIROOTFS}/etc/modprobe.d" \
  "${AIROOTFS}/etc/sysctl.d" \
  "${AIROOTFS}/etc/systemd/system" \
  "${AIROOTFS}/etc/systemd/coredump.conf.d" \
  "${AIROOTFS}/etc/NetworkManager/conf.d" \
  "${AIROOTFS}/etc/udev/rules.d" \
  "${AIROOTFS}/etc/pacman.d/hooks" \
  "${AIROOTFS}/etc/modules-load.d" \
  "${AIROOTFS}/usr/local/sbin" \
  "${AIROOTFS}/usr/local/src/venue-batfix" \
  "${AIROOTFS}/root/venue-fix-src"

log "Copying modprobe configurations..."
cp "${TEMP_DIR}/upstream/etc/modprobe.d/ath6kl.conf" "${AIROOTFS}/etc/modprobe.d/"
cp "${TEMP_DIR}/upstream/etc/modprobe.d/cfg80211-regdom.conf" "${AIROOTFS}/etc/modprobe.d/"

log "Copying sysctl power management configurations..."
cp "${TEMP_DIR}/upstream/etc/sysctl.d/99-venue-power.conf" "${AIROOTFS}/etc/sysctl.d/"
cp "${TEMP_DIR}/upstream/etc/sysctl.d/99-zram-tablet.conf" "${AIROOTFS}/etc/sysctl.d/"

log "Copying systemd configurations..."
cp "${TEMP_DIR}/upstream/etc/systemd/zram-generator.conf" "${AIROOTFS}/etc/systemd/"
cp "${TEMP_DIR}/upstream/etc/systemd/coredump.conf.d/disable-storage.conf" "${AIROOTFS}/etc/systemd/coredump.conf.d/"
cp "${TEMP_DIR}/upstream/etc/systemd/system/ath6kl-tune.service" "${AIROOTFS}/etc/systemd/system/"
cp "${TEMP_DIR}/upstream/etc/systemd/system/bt-venue.service" "${AIROOTFS}/etc/systemd/system/"

log "Copying NetworkManager configurations..."
cp "${TEMP_DIR}/upstream/etc/NetworkManager/conf.d/30-no-mac-rand.conf" "${AIROOTFS}/etc/NetworkManager/conf.d/"

log "Copying udev rules..."
cp "${TEMP_DIR}/upstream/etc/udev/rules.d/99-emmc-fixed-disk.rules" "${AIROOTFS}/etc/udev/rules.d/"

log "Copying pacman hooks..."
cp "${TEMP_DIR}/upstream/etc/pacman.d/hooks/zz-arch-launcher-icon.hook" "${AIROOTFS}/etc/pacman.d/hooks/"
cp "${TEMP_DIR}/upstream/etc/pacman.d/hooks/venue-batfix.hook" "${AIROOTFS}/etc/pacman.d/hooks/"

log "Copying module load configuration..."
cp "${TEMP_DIR}/upstream/etc/modules-load.d/venue-batfix.conf" "${AIROOTFS}/etc/modules-load.d/"

log "Copying hardware fix scripts..."
cp "${TEMP_DIR}/upstream/usr/local/sbin/ath6kl-tune.sh" "${AIROOTFS}/usr/local/sbin/"
cp "${TEMP_DIR}/upstream/usr/local/sbin/arch-launcher-icon.sh" "${AIROOTFS}/usr/local/sbin/"
cp "${TEMP_DIR}/upstream/usr/local/sbin/venue-batfix-build.sh" "${AIROOTFS}/usr/local/sbin/"
chmod +x "${AIROOTFS}/usr/local/sbin"/*.sh

log "Copying batfix kernel module source..."
cp "${TEMP_DIR}/upstream/usr/local/src/venue-batfix/batfix.c" "${AIROOTFS}/usr/local/src/venue-batfix/"
cp "${TEMP_DIR}/upstream/usr/local/src/venue-batfix/Makefile" "${AIROOTFS}/usr/local/src/venue-batfix/"

log "Copying source files for build-time compilation..."
cp "${TEMP_DIR}/upstream/acpi/bt0off.dsl" "${AIROOTFS}/root/venue-fix-src/"
cp "${TEMP_DIR}/upstream/src/bthci.c" "${AIROOTFS}/root/venue-fix-src/"

# === Step 3: Attribution file ===
log "Creating attribution file..."
mkdir -p "${AIROOTFS}/usr/share/doc"
cat > "${AIROOTFS}/usr/share/doc/DELL_VENUE_FIXES_ATTRIBUTION.txt" <<'ATTRIBUTION'
Dell Venue 8 Pro 5830 Hardware Fixes
====================================

This system includes hardware fixes and support tools from:
  https://github.com/ramonvanraaij/dell-venue-8-pro

Author: Rúmon van Raaij
Blog: https://ramon.vanraaij.eu/the-bluetooth-that-was-never-dead-my-dell-venue-8-pro-baud-rate-journey/

Included Components:
  - Bluetooth bring-up (bthci.c, bt-venue.service) — BSD 3-Clause
  - ACPI override (bt0off.dsl) — BSD 3-Clause
  - Wi-Fi tuning scripts (ath6kl-tune.sh, ath6kl-tune.service) — BSD 3-Clause
  - Battery glitch filter (batfix kernel module) — GPL-2.0
  - Power management configs (sysctl, systemd) — BSD 3-Clause
  - NetworkManager & udev configurations — BSD 3-Clause
  - Launcher icon replacement script (arch-launcher-icon.sh) — BSD 3-Clause

All files retain their original copyright and license headers.

This archiso build orchestrates these components into a seamless automated deployment.
ATTRIBUTION

log "Integration complete. All hardware fixes embedded in temporary archiso tree."

# === Step 4: Build ISO ===
log "Building ISO with mkarchiso..."
log "This may take 20-40 minutes depending on internet speed and CPU."

mkdir -p "${OUTPUT_DIR}"
sudo mkdir -p "${WORK_DIR}"

# -w workdir is required — mkarchiso uses realpath() on it and fails with an
# empty string if it is omitted or if the directory does not already exist.
sudo mkarchiso -v -w "${WORK_DIR}" -o "${OUTPUT_DIR}" "${BUILD_ARCHISO_DIR}"

# Clean up work directory (can be several GB)
sudo rm -rf "${WORK_DIR}"

# Return ownership of output artifacts to the invoking user when possible and needed.
if [ -d "${OUTPUT_DIR}" ]; then
    if find "${OUTPUT_DIR}" \! -user "${REAL_USER}" -print -quit 2>/dev/null | grep -q .; then
        log "Adjusting ownership of output directory to ${REAL_USER}:${REAL_GROUP}..."
        if ! sudo chown -R "${REAL_USER}:${REAL_GROUP}" "${OUTPUT_DIR}" 2>/dev/null; then
            log "Skipping ownership adjustment; filesystem or mount options do not permit chown."
        fi
    else
        log "Output directory already owned by ${REAL_USER}; no chown needed."
    fi
fi

if ls "${OUTPUT_DIR}"/arch-*.iso 1>/dev/null 2>&1; then
    ISO_FILE="$(ls -1 "${OUTPUT_DIR}"/arch-*.iso | head -1)"
    ISO_SIZE="$(du -h "${ISO_FILE}" | cut -f1)"
    log "✓ ISO build successful!"
    log "  ISO file : ${ISO_FILE}"
    log "  Size     : ${ISO_SIZE}"
    log ""
    log "Next steps:"
    log "  1. Write to USB: sudo dd if=${ISO_FILE} of=/dev/sdX bs=4M status=progress && sync"
    log "  2. Boot Dell Venue 8 Pro 5830 from USB"
    log "  3. Wait for automatic installation (~15 minutes)"
    log "  4. Login with arch:arch"
else
    error "ISO build failed. Check mkarchiso output above."
fi
