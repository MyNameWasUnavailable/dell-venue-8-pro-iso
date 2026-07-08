#!/usr/bin/env bash
# Automated installer for Dell Venue 8 Pro 5830 - runs in archiso
# This script partitions the eMMC, installs Arch Linux with all fixes,
# and configures the system for unattended boot into Plasma Mobile.
#
# The hardware fixes are pre-integrated from ramonvanraaij/dell-venue-8-pro
# and copied into the airootfs at build time by build.sh.

set -o errexit -o nounset -o pipefail

# Configuration
TARGET_DEVICE="/dev/mmcblk1"  # Internal eMMC
TARGET_MOUNT="/mnt"
BOOT_SIZE="512M"
ROOT_SIZE=""  # Use remaining space

log() { echo "[INSTALL] $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# === STEP 1: Verify target device ===
log "Verifying target device..."
if [ ! -b "${TARGET_DEVICE}" ]; then
    error "Target device ${TARGET_DEVICE} not found. Aborting."
fi

# === STEP 2: Partition eMMC ===
log "Partitioning ${TARGET_DEVICE}..."
sfdisk "${TARGET_DEVICE}" <<EOF
label: gpt
unit: sectors

${TARGET_DEVICE}p1 : start=        2048, size=     1050624, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, bootable
${TARGET_DEVICE}p2 : type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF

log "Formatting partitions..."
mkfs.fat -F 32 "${TARGET_DEVICE}p1"
mkfs.btrfs -f "${TARGET_DEVICE}p2"

# === STEP 3: Mount filesystems ===
log "Mounting filesystems..."
mount "${TARGET_DEVICE}p2" "${TARGET_MOUNT}"
mkdir -p "${TARGET_MOUNT}/boot"
mount "${TARGET_DEVICE}p1" "${TARGET_MOUNT}/boot"

# Create btrfs subvolumes
btrfs subvolume create "${TARGET_MOUNT}/@"
btrfs subvolume create "${TARGET_MOUNT}/@home"
btrfs subvolume create "${TARGET_MOUNT}/@var"

# Remount with subvol
umount -R "${TARGET_MOUNT}"
mount -o subvol=@,compress=zstd:1,relatime "${TARGET_DEVICE}p2" "${TARGET_MOUNT}"
mkdir -p "${TARGET_MOUNT}/home"
mount -o subvol=@home,compress=zstd:1,relatime "${TARGET_DEVICE}p2" "${TARGET_MOUNT}/home"
mkdir -p "${TARGET_MOUNT}/var"
mount -o subvol=@var,compress=zstd:1,relatime "${TARGET_DEVICE}p2" "${TARGET_MOUNT}/var"

# === STEP 4: Bootstrap Arch Linux ===
log "Bootstrapping Arch Linux..."
pacstrap -c "${TARGET_MOUNT}" base linux linux-firmware linux-headers intel-ucode

# === STEP 5: Generate fstab ===
log "Generating fstab..."
genfstab -U "${TARGET_MOUNT}" >> "${TARGET_MOUNT}/etc/fstab"

# === STEP 6: Chroot + Configure system ===
log "Entering chroot for system configuration..."
arch-chroot "${TARGET_MOUNT}" /usr/bin/bash << 'CHROOT'
set -o errexit -o nounset -o pipefail

log() { echo "[CHROOT] $*" >&2; }

# --- Localization ---
log "Setting up localization..."
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

# --- Timezone ---
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# --- Hostname ---
echo "venue-8-pro" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 venue-8-pro.localdomain venue-8-pro
EOF

# --- System clock ---
log "Enabling NTP..."
systemctl enable systemd-timesyncd

# --- Essential packages ---
log "Installing essential packages..."
pacman -S --noconfirm --needed \
  base-devel acpica iasl \
  btrfs-progs \
  wireless-regdb bluez bluez-utils bluez-deprecated-tools \
  networkmanager iw \
  powertop acpi thermald power-profiles-daemon zram-generator

# --- Plasma Mobile + KDE ---
log "Installing Plasma Mobile desktop..."
pacman -S --noconfirm --needed \
  plasma-mobile plasma-desktop kde-system-meta \
  sddm sddm-kcm archlinux-themes-sddm \
  plasma-workspace-wallpapers oxygen breeze-gtk breeze-icons \
  kde-gtk-config kdeplasma-addons kscreen kdeconnect \
  kinfocenter kmenuedit systemsettings \
  plasma-systemmonitor plasma-firewall kwalletmanager \
  drkonqi polkit-kde-agent discover print-manager \
  wacomtablet iio-sensor-proxy \
  qt5-wayland qt6-wayland qt5-quickcontrols layer-shell-qt5 \
  pipewire pipewire-alsa pipewire-jack pipewire-pulse wireplumber libpulse \
  gst-plugin-pipewire alsa-utils \
  qmlkonsole spectacle nano gvim ex-vi-compat \
  fastfetch tmux git openssh wget octopi \
  ttf-dejavu ttf-liberation

# --- User account: arch / arch with sudo ---
log "Creating user 'arch' with sudo access..."
pacman -S --noconfirm sudo
groupadd -f wheel
useradd -m -g wheel -s /bin/bash arch
echo 'arch:arch' | chpasswd

# Enable wheel group for sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# --- Root password (also 'arch' for recovery) ---
echo 'root:arch' | chpasswd

# --- systemd-boot configuration ---
log "Configuring systemd-boot..."
bootctl --esp-path=/boot install 2>/dev/null || true

cat > /boot/loader/loader.conf <<LOADEREOF
default arch.conf
timeout 3
console-mode max
editor no
LOADEREOF

cat > /boot/loader/entries/arch.conf <<ENTRYEOF
title   Arch Linux (Dell Venue 8 Pro 5830)
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=UUID=PLACEHOLDER rw rootflags=subvol=@ intel_idle.max_cstate=1 panic=10 zswap.enabled=0
ENTRYEOF

# Replace UUID placeholder
ROOT_UUID="$(blkid -s UUID -o value /dev/mmcblk1p2)"
sed -i "s|UUID=PLACEHOLDER|UUID=${ROOT_UUID}|" /boot/loader/entries/arch.conf

# --- ACPI override (bt0off) ---
log "Building ACPI bt0off override..."
mkdir -p /tmp/acpi_build
cd /tmp/acpi_build

# Use precompiled source from venue-fix-src (copied at build time)
cp /root/venue-fix-src/bt0off.dsl .

iasl -tc bt0off.dsl
mkdir -p kernel/firmware/acpi
cp bt0off.aml kernel/firmware/acpi/
find kernel | cpio -H newc --create --quiet > /boot/acpi_override.img

sed -i 's|^initrd  /intel-ucode.img|initrd  /acpi_override.img\ninitrd  /intel-ucode.img|' /boot/loader/entries/arch.conf

cd /
rm -rf /tmp/acpi_build

# --- Build and install bthci ---
log "Building bthci Bluetooth bring-up tool..."
gcc -O2 -o /usr/local/sbin/bthci /root/venue-fix-src/bthci.c
chmod 755 /usr/local/sbin/bthci

# --- Build and install batfix kernel module ---
log "Building batfix kernel module..."
/usr/local/sbin/venue-batfix-build.sh

# --- Fix configs already in place (copied by build.sh) ---
log "Fixing permissions on fix scripts..."
chmod +x /usr/local/sbin/ath6kl-tune.sh
chmod +x /usr/local/sbin/arch-launcher-icon.sh
chmod +x /usr/local/sbin/venue-batfix-build.sh

# --- Enable services ---
log "Enabling services..."
systemctl enable sddm NetworkManager thermald power-profiles-daemon
systemctl enable ath6kl-tune.service bt-venue.service

# --- Copy attribution file ---
log "Installing attribution file..."
mkdir -p /usr/share/doc
cat > /usr/share/doc/DELL_VENUE_FIXES_ATTRIBUTION.txt <<'ATTRIBUTION'
Dell Venue 8 Pro 5830 Hardware Fixes Attribution
==================================================

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

This automated installation was orchestrated by:
  https://github.com/MyNameWasUnavailable/dell-venue-8-pro-iso
ATTRIBUTION

log "System configuration complete!"
CHROOT

log "Installation successful! Unmounting and rebooting..."
umount -R "${TARGET_MOUNT}"

sleep 3
reboot -f