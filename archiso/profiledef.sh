#!/usr/bin/env bash
# shellcheck disable=SC2034
# archiso profile definition for Dell Venue 8 Pro 5830 automated install
# Bay Trail (Atom Z3740D) is UEFI-only — no legacy BIOS/syslinux needed.

iso_name="arch-venue-8-pro"
iso_label="ARCH_VENUE8PRO_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="MyNameWasUnavailable <https://github.com/MyNameWasUnavailable/dell-venue-8-pro-iso>"
iso_application="Arch Linux - Dell Venue 8 Pro 5830 Automated Installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')

file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/install-venue.sh"]="0:0:755"
  ["/usr/local/sbin"]="0:0:755"
  ["/usr/local/sbin/ath6kl-tune.sh"]="0:0:755"
  ["/usr/local/sbin/arch-launcher-icon.sh"]="0:0:755"
  ["/usr/local/sbin/venue-batfix-build.sh"]="0:0:755"
)
