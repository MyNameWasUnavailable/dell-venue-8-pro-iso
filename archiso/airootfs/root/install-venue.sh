#!/usr/bin/env bash
# Automated installer for Dell Venue 8 Pro 5830 - runs in archiso live environment.
# Partitions the eMMC, installs Arch Linux with all fixes, and configures the
# system for unattended boot into Plasma Mobile.
#
# Hardware identifiers (Wi-Fi interface, MAC addresses, eMMC device) are detected
# automatically from the live system at install time and substituted into any
# config files that reference them.
#
# The hardware fixes are pre-integrated from ramonvanraaij/dell-venue-8-pro
# and copied into the airootfs at build time by build.sh.

set -o errexit -o nounset -o pipefail

TARGET_MOUNT="/mnt"
BOOT_SIZE="512M"

log()   { echo "[INSTALL] $*" >&2; }
warn()  { echo "[WARN]    $*" >&2; }
error() { echo "[ERROR]   $*" >&2; exit 1; }

# =============================================================================
# STEP 0: Auto-detect hardware identifiers from the live system
# =============================================================================
log "--- Hardware detection ---"

# --- eMMC / target block device ---
# Prefer a non-removable internal mmc device; explicitly reject removable/USB media.
detect_install_target() {
    local candidate sysbase removable size transport

    for candidate in /dev/mmcblk1 /dev/mmcblk0 /dev/nvme0n1 /dev/sda; do
        [ -b "${candidate}" ] || continue
        sysbase="/sys/class/block/$(basename "${candidate}")"
        [ -d "${sysbase}" ] || continue

        removable="$(cat "${sysbase}/removable" 2>/dev/null || echo 1)"
        size="$(cat "${sysbase}/size" 2>/dev/null || echo 0)"
        transport="$(readlink -f "${sysbase}/device/subsystem" 2>/dev/null || true)"

        if [[ "${candidate}" == /dev/mmcblk* ]]; then
            if [ "${removable}" = "0" ] && [ "${size}" -gt 0 ]; then
                echo "${candidate}"
                return 0
            fi
            continue
        fi

        if [ "${removable}" = "1" ]; then
            warn "Skipping removable block device ${candidate}"
            continue
        fi

        if [[ "${transport}" == *usb* ]]; then
            warn "Skipping USB-backed block device ${candidate}"
            continue
        fi

        if [ "${size}" -gt 0 ]; then
            echo "${candidate}"
            return 0
        fi
    done

    return 1
}

TARGET_DEVICE="$(detect_install_target)" \
    || error "No safe internal install target found. Refusing to install to removable or USB-backed storage."
log "Target device : ${TARGET_DEVICE}"

# Derive partition suffix: mmcblk* and nvme* use 'p1'/'p2', sda uses '1'/'2'
case "${TARGET_DEVICE}" in
    *mmcblk*|*nvme*) PART_SEP="p" ;;
    *)               PART_SEP=""  ;;
esac
BOOT_PART="${TARGET_DEVICE}${PART_SEP}1"
ROOT_PART="${TARGET_DEVICE}${PART_SEP}2"

# --- Wi-Fi interface ---
# Use 'iw dev' first; fall back to scanning /sys/class/net for a wl* interface.
detect_wifi_iface() {
    local iface
    iface="$(iw dev 2>/dev/null | awk '/^\s*Interface /{print $2}' | head -1)"
    if [ -n "${iface}" ]; then echo "${iface}"; return 0; fi
    for sysif in /sys/class/net/wl*; do
        [ -e "${sysif}" ] && echo "$(basename "${sysif}")" && return 0
    done
    return 1
}
if WIFI_IFACE="$(detect_wifi_iface)"; then
    WIFI_MAC="$(cat "/sys/class/net/${WIFI_IFACE}/address" 2>/dev/null || echo '')"
    log "Wi-Fi interface: ${WIFI_IFACE}  MAC: ${WIFI_MAC:-unknown}"
else
    WIFI_IFACE="wlan0"
    WIFI_MAC=""
    warn "No Wi-Fi interface detected — defaulting to 'wlan0'. Configs will use that name."
fi

# --- Bluetooth MAC (best-effort; adapter may not be powered yet) ---
BT_MAC=""
if command -v hciconfig &>/dev/null; then
    BT_MAC="$(hciconfig hci0 2>/dev/null | awk '/BD Address/{print $3}' || true)"
fi
if [ -z "${BT_MAC}" ] && [ -f /sys/class/bluetooth/hci0/address ]; then
    BT_MAC="$(cat /sys/class/bluetooth/hci0/address 2>/dev/null || true)"
fi
log "Bluetooth MAC  : ${BT_MAC:-not detected (will be populated at first boot)}"

# --- Tablet IP (informational only) ---
TABLET_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
log "Tablet IP      : ${TABLET_IP:-not detected}"

log "--- End hardware detection ---"

# =============================================================================
# STEP 1: Verify target device
# =============================================================================
log "Verifying target device ${TARGET_DEVICE}..."
[ -b "${TARGET_DEVICE}" ] || error "Target device ${TARGET_DEVICE} not found. Aborting."

# =============================================================================
# STEP 2: Partition eMMC
# =============================================================================
log "Partitioning ${TARGET_DEVICE}..."
sfdisk "${TARGET_DEVICE}" <<EOF
label: gpt
unit: sectors

${BOOT_PART} : start=        2048, size=     1050624, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, bootable
${ROOT_PART} : type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF

log "Formatting partitions..."
mkfs.fat -F 32 "${BOOT_PART}"
mkfs.btrfs -f  "${ROOT_PART}"

# =============================================================================
# STEP 3: Mount filesystems
# =============================================================================
log "Mounting filesystems..."
mount "${ROOT_PART}" "${TARGET_MOUNT}"
mkdir -p "${TARGET_MOUNT}/boot"
mount "${BOOT_PART}" "${TARGET_MOUNT}/boot"

btrfs subvolume create "${TARGET_MOUNT}/@"
btrfs subvolume create "${TARGET_MOUNT}/@home"
btrfs subvolume create "${TARGET_MOUNT}/@var"

umount -R "${TARGET_MOUNT}"
mount -o subvol=@,compress=zstd:1,relatime     "${ROOT_PART}" "${TARGET_MOUNT}"
mkdir -p "${TARGET_MOUNT}/home"
mount -o subvol=@home,compress=zstd:1,relatime "${ROOT_PART}" "${TARGET_MOUNT}/home"
mkdir -p "${TARGET_MOUNT}/var"
mount -o subvol=@var,compress=zstd:1,relatime  "${ROOT_PART}" "${TARGET_MOUNT}/var"
mkdir -p "${TARGET_MOUNT}/boot"
mount "${BOOT_PART}" "${TARGET_MOUNT}/boot"

# =============================================================================
# STEP 4: Bootstrap Arch Linux
# =============================================================================
log "Bootstrapping Arch Linux (pacstrap)..."
pacstrap -c "${TARGET_MOUNT}" base linux linux-firmware linux-headers intel-ucode

# =============================================================================
# STEP 5: Generate fstab
# =============================================================================
log "Generating fstab..."
genfstab -U "${TARGET_MOUNT}" >> "${TARGET_MOUNT}/etc/fstab"

# =============================================================================
# STEP 6: Substitute hardware identifiers in copied upstream config files
# =============================================================================
log "Substituting hardware identifiers in config files..."

substitute_placeholders() {
    local file="$1"
    grep -qE '<(WIFI_MAC|WIFI_IFACE|BT_MAC|TABLET_IP)>' "${file}" 2>/dev/null || return 0

    log "  Patching placeholders in: ${file}"
    [ -n "${WIFI_MAC}" ]   && sed -i "s|<WIFI_MAC>|${WIFI_MAC}|g"     "${file}"
    [ -n "${WIFI_IFACE}" ] && sed -i "s|<WIFI_IFACE>|${WIFI_IFACE}|g" "${file}"
    [ -n "${BT_MAC}" ]     && sed -i "s|<BT_MAC>|${BT_MAC}|g"         "${file}"
    [ -n "${TABLET_IP}" ]  && sed -i "s|<TABLET_IP>|${TABLET_IP}|g"   "${file}"
}

while IFS= read -r -d '' f; do
    file "${f}" 2>/dev/null | grep -q 'text' || continue
    substitute_placeholders "${f}"
done < <(find "${TARGET_MOUNT}/etc" "${TARGET_MOUNT}/usr/local" -type f -print0 2>/dev/null)

log "Placeholder substitution complete."

# =============================================================================
# STEP 7: Write a hardware-info file into the installed system
# =============================================================================
mkdir -p "${TARGET_MOUNT}/etc/venue-hardware"
cat > "${TARGET_MOUNT}/etc/venue-hardware/detected.conf" <<HWEOF
# Auto-detected at ISO install time by install-venue.sh
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
TARGET_DEVICE="${TARGET_DEVICE}"
WIFI_IFACE="${WIFI_IFACE}"
WIFI_MAC="${WIFI_MAC}"
BT_MAC="${BT_MAC}"
TABLET_IP="${TABLET_IP}"
HWEOF
log "Hardware info written to /etc/venue-hardware/detected.conf"

# =============================================================================
# STEP 8: Chroot + configure system
# =============================================================================
log "Entering chroot for system configuration..."

WIFI_IFACE_VAL="${WIFI_IFACE}"
ROOT_PART_VAL="${ROOT_PART}"

arch-chroot "${TARGET_MOUNT}" /usr/bin/bash << CHROOT
set -o errexit -o nounset -o pipefail

log() { echo "[CHROOT] \$*" >&2; }

log "Setting up localization..."
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us"        > /etc/vconsole.conf

ln -sf /usr/share/zoneinfo/Australia/Sydney /etc/localtime
hwclock --systohc

systemctl mask systemd-firstboot.service

echo "venue-8-pro" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 venue-8-pro.localdomain venue-8-pro
EOF

log "Enabling NTP..."
systemctl enable systemd-timesyncd

log "Installing essential packages..."
pacman -S --noconfirm --needed \
    base-devel acpica iasl \
    btrfs-progs \
    wireless-regdb bluez bluez-utils bluez-deprecated-tools \
    networkmanager iw \
    powertop acpi thermald power-profiles-daemon zram-generator

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

log "Creating user 'arch' with sudo access..."
pacman -S --noconfirm sudo
groupadd -f wheel
useradd -m -g wheel -s /bin/bash arch
echo 'arch:arch' | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo 'root:arch' | chpasswd

log "Configuring NetworkManager for interface ${WIFI_IFACE_VAL}..."
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/10-venue-iface.conf <<NM
# Auto-generated by install-venue.sh — detected interface: ${WIFI_IFACE_VAL}
[keyfile]
unmanaged-devices=none

[device-${WIFI_IFACE_VAL}]
match-device=interface-name:${WIFI_IFACE_VAL}
managed=true
NM

log "Configuring systemd-boot..."
bootctl --esp-path=/boot install
[ -f /boot/EFI/systemd/systemd-bootx64.efi ] || [ -f /boot/EFI/BOOT/BOOTX64.EFI ] || \
    [ -f /boot/EFI/systemd/systemd-bootia32.efi ] || [ -f /boot/EFI/BOOT/BOOTIA32.EFI ] || \
    { echo "[CHROOT] systemd-boot files not found after bootctl install" >&2; exit 1; }

mkdir -p /boot/loader/entries
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

ROOT_UUID="\$(blkid -s UUID -o value ${ROOT_PART_VAL})"
sed -i "s|UUID=PLACEHOLDER|UUID=\${ROOT_UUID}|" /boot/loader/entries/arch.conf

log "Building ACPI bt0off override..."
mkdir -p /tmp/acpi_build
cd /tmp/acpi_build
cp /root/venue-fix-src/bt0off.dsl .
iasl -tc bt0off.dsl
mkdir -p kernel/firmware/acpi
cp bt0off.aml kernel/firmware/acpi/
find kernel | cpio -H newc --create --quiet > /boot/acpi_override.img
sed -i 's|^initrd  /intel-ucode.img|initrd  /acpi_override.img\ninitrd  /intel-ucode.img|' \
    /boot/loader/entries/arch.conf
cd /
rm -rf /tmp/acpi_build

log "Building bthci Bluetooth bring-up tool..."
gcc -O2 -o /usr/local/sbin/bthci /root/venue-fix-src/bthci.c
chmod 755 /usr/local/sbin/bthci

log "Building batfix kernel module..."
/usr/local/sbin/venue-batfix-build.sh

log "Setting permissions on fix scripts..."
chmod +x /usr/local/sbin/ath6kl-tune.sh
chmod +x /usr/local/sbin/arch-launcher-icon.sh
chmod +x /usr/local/sbin/venue-batfix-build.sh

log "Enabling services..."
systemctl enable NetworkManager thermald power-profiles-daemon
systemctl enable ath6kl-tune.service bt-venue.service
systemctl set-default multi-user.target

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

log "Installation successful! Unmounting filesystems..."
umount -R "${TARGET_MOUNT}"

log "Rebooting in 5 seconds..."
sleep 5
reboot -f
