# Dell Venue 8 Pro 5830 - Automated Arch Linux ISO Builder

**Build a completely hands-off Arch Linux install ISO with Plasma Mobile and all Dell Venue 8 Pro fixes integrated.**

This toolkit creates an ISO that will:
- Automatically partition and format the eMMC
- Install Arch Linux base system
- Deploy Plasma Mobile (touch-optimized GUI)
- Apply all hardware fixes from [ramonvanraaij/dell-venue-8-pro](https://github.com/ramonvanraaij/dell-venue-8-pro)
  - Bluetooth at 3.6864 Mbaud (AR3002 @ ttyS4)
  - Wi-Fi stability (ath6kl 37-min disconnect fix + 5GHz regulatory domain)
  - Battery transient-zero glitch filtering (batfix kernel module)
  - Power management (zram swap, thermald, Bay Trail C-state limiting)
- Create user `arch:arch` with sudo access
- Boot directly into Plasma Mobile

**Result**: Write ISO to USB → Insert in tablet → Boot → ~15 minutes later → Fully working Plasma Mobile desktop with all hardware working.

---

## Attribution

**This automated installer is built on the excellent work of [Rúmon van Raaij](https://github.com/ramonvanraaij) and the Dell Venue 8 Pro 5830 fixes published in [ramonvanraaij/dell-venue-8-pro](https://github.com/ramonvanraaij/dell-venue-8-pro).**

The archiso build scripts download and integrate all configurations, Bluetooth bringup tools, Wi-Fi tuning scripts, battery fixes, and systemd service units from that repository during the build process. Full attribution and licensing is maintained:

- **Hardware fixes** (Bluetooth, Wi-Fi, power management): [BSD 3-Clause](https://github.com/ramonvanraaij/dell-venue-8-pro/blob/main/LICENSE.md) — Rúmon van Raaij
- **batfix kernel module** (battery glitch filter): [GPL-2.0](https://github.com/ramonvanraaij/dell-venue-8-pro/blob/main/LICENSE.md) — Rúmon van Raaij
- **Archiso build infrastructure**: [GPL-3.0+](https://gitlab.archlinux.org/archlinux/archiso/-/blob/master/LICENSE) — Arch Linux
- **Plasma Mobile**: [LGPL](https://invent.kde.org/plasma-mobile/) — KDE Project

---

## Quick Start

### Prerequisites (on build machine with Arch Linux)

```bash
sudo pacman -S archiso git
```

### Build the ISO

```bash
# Clone this repository
git clone https://github.com/MyNameWasUnavailable/dell-venue-8-pro-iso.git
cd dell-venue-8-pro-iso

# Build (takes ~20-40 min depending on internet speed)
sudo mkdir -p /tmp/archiso-out
sudo bash ./build.sh /tmp/archiso-out

# Find the ISO
ls -lh /tmp/archiso-out/arch-*.iso
```

### Write to USB

**Linux:**
```bash
sudo dd if=/tmp/archiso-out/arch-*.iso of=/dev/sdX bs=4M status=progress && sync
```

**macOS:**
```bash
diskutil unmountDisk /dev/diskX
sudo dd if=/tmp/archiso-out/arch-*.iso of=/dev/rdiskX bs=4m && sync
sudo diskutil ejectDisk /dev/diskX
```

**Windows:** Use [Balena Etcher](https://www.balena.io/etcher/) or Rufus.

### Install on Tablet

1. Insert USB into Dell Venue 8 Pro 5830
2. Power on, boot from USB (may need BIOS menu - typically F2 or DEL)
3. Wait for automatic installation (~15 min)
4. System reboots into Plasma Mobile
5. Login: `arch` / Password: `arch`

---

## Build Process

The `build.sh` script:

1. **Clones the upstream repository** from `ramonvanraaij/dell-venue-8-pro`
2. **Copies all fixes** into the archiso airootfs:
   - Modprobe configs (ath6kl, cfg80211 regulatory domain)
   - systemd services (ath6kl-tune, bt-venue)
   - systemd configs (zram, coredump, modules-load)
   - NetworkManager configs (MAC randomization)
   - udev rules (eMMC classification)
   - Shell scripts (ath6kl-tune.sh, arch-launcher-icon.sh, venue-batfix-build.sh)
   - Kernel module source (batfix)
3. **Integrates the bthci Bluetooth tool source** (compiled during ISO installation)
4. **Runs mkarchiso** to build the final ISO
5. **Embeds ACPI bt0off override** during installation (compiled at first boot)

All source files retain their original copyright and licensing. The archiso profile orchestrates them into a seamless automated deployment.

---

## Directory Structure

```
dell-venue-8-pro-iso/
├── build.sh                         Main build script (clones upstream, builds ISO)
├── README.md                        This file
├── LICENSE                          License info
│
└── archiso/
    ├── profiledef.sh                archiso profile metadata
    ├── packages.x86_64              all packages (base + GUI + tools)
    │
    └── airootfs/
        ├── root/
        │   ├── install-venue.sh     automated installation script (orchestrates fixes)
        │   ├── .bashrc              shell customization
        │   └── .zprofile            auto-start installation
        │
        └── etc/
            ├── pacman.conf          package manager config
            └── systemd/system/
                └── venue-install.service
```

---

## Customization

### Change Username/Password

Edit `archiso/airootfs/root/install-venue.sh`, find:
```bash
useradd -m -g wheel -s /bin/bash arch
echo 'arch:arch' | chpasswd
```

Change to your desired user and password.

### Add/Remove Packages

Edit `archiso/packages.x86_64` and add/remove package names (one per line).

Common additions:
- `firefox` — web browser
- `vlc` — media player
- `blender` — 3D modeling (large!)
- `gimp` — image editor

### Disable Auto-Start Installation

Comment out the startup code in `archiso/airootfs/root/.zprofile`. Then manually run:
```bash
sudo /root/install-venue.sh
```

### Custom Hostname

Edit `archiso/airootfs/root/install-venue.sh`, find:
```bash
echo "venue-8-pro" > /etc/hostname
```

Change to your desired hostname.

---

## What Gets Installed

### Base System
- Arch Linux kernel + firmware
- systemd-boot bootloader
- Intel microcode updates
- btrfs filesystem tools

### Desktop (Plasma Mobile)
- Plasma Mobile shell (touch-optimized)
- KDE Plasma 6 components
- SDDM display manager (auto-login)
- Wayland (modern display server)

### Hardware Support
- BlueZ + Bluetooth utilities
- NetworkManager (Wi-Fi)
- Touch screen support (wacomtablet, iio-sensor-proxy)
- Audio (PipeWire)

### Hardware Fixes (from ramonvanraaij/dell-venue-8-pro)

**Bluetooth**: 
- ACPI override (bt0off) disables ACPI Bluetooth serdev child
- bthci tool powers AR3002 @ 3.6864 Mbaud (non-standard rate, POSIX termios can't set it)
- bt-venue.service runs bthci at boot
- Full ROM-level HCI-capable, no firmware download needed

**Wi-Fi**:
- ath6kl debugfs tuning (disconnect_timeout=60, bgscan_interval=0)
- Prevents self-deauth after ~37 minutes (firmware patience was too short)
- 5GHz regulatory domain (NL) for DFS channel support
- MAC randomization disabled (ath6kl doesn't support it)

**Battery**:
- batfix kernel module (kretprobe on power_supply_get_property)
- Filters transient all-zero readings on AC plug/unplug
- No false "battery critical" warnings
- Real low-battery reporting still works

**Power Management**:
- zram-generator: compressed RAM-backed swap (2GB → ~4-6GB effective)
- thermald: thermal management for fanless tablet
- Bay Trail C-state limiter (intel_idle.max_cstate=1): prevents deep-idle CPU hangs
- NMI watchdog disabled (not needed, saves power)
- Dirty writeback throttling (eMMC wear reduction)

**Storage**:
- eMMC reclassified from SD/MMC card to fixed disk (udev rule)
- System Monitor "Disks" widget now shows eMMC usage

### Utilities
- Terminal (qmlkonsole)
- Text editors (nano, vim)
- System monitor, file manager, calculator
- Git, wget, openssh

---

## Troubleshooting

### ISO won't build

**Problem**: `mkarchiso: command not found`
```bash
sudo pacman -S archiso
```

**Problem**: Clone of ramonvanraaij/dell-venue-8-pro fails
- Ensure internet connectivity
- Try manual clone: `git clone https://github.com/ramonvanraaij/dell-venue-8-pro.git`
- Check GitHub API rate limits

### ISO won't boot

- Verify USB was written correctly: `sudo blkid /dev/sdX1` (should show ISO9660)
- Try writing with `dd` instead of GUI tool
- Ensure Secure Boot is disabled in tablet BIOS

### Installation fails mid-way

- Check available space on USB: `df /mnt`
- Verify eMMC is detected: `lsblk` (should show `/dev/mmcblk1` or `/dev/sda`)
- Check system journal: `journalctl -xe`

### Can't find eMMC

- Some tablets enumerate as `/dev/sda` instead of `/dev/mmcblk1`
- Edit `archiso/airootfs/root/install-venue.sh` and change `TARGET_DEVICE` accordingly
- Use `lsblk` to identify the correct device

### Bluetooth missing after install

- Verify ACPI override: `ls -la /boot/acpi_override.img` (should exist)
- Check boot entry: `cat /boot/loader/entries/arch.conf` (should include acpi_override initrd)
- Verify service started: `systemctl status bt-venue.service`
- Check ttyS4: `ls -la /dev/ttyS4` (should exist)
- View logs: `journalctl -u bt-venue.service -n 20`

### Wi-Fi drops every ~37 minutes

This means `ath6kl-tune.service` didn't run at boot:
- Check: `systemctl status ath6kl-tune.service`
- View logs: `journalctl -u ath6kl-tune.service -n 20`
- Manually apply: `sudo /usr/local/sbin/ath6kl-tune.sh`
- Check that `/sys/kernel/debug/ieee80211/phy*/ath6kl` exists

### Touch input not working

- Calibrate: Settings → Input Devices → Touch Screen
- Verify wacomtablet loaded: `lsmod | grep wacom`
- Check udev: `udevadm info /dev/input/event*`

---

## Post-Installation

### First Boot

1. Plasma Mobile splash appears (may take 1-2 min on first boot)
2. System auto-logs in as `arch`
3. Tap anywhere to unlock, then tap Activities → System Settings to configure

### Essential Settings

- **Time/Date**: System Settings → Date & Time (set timezone)
- **Display**: System Settings → Display & Monitor (touch calibration)
- **Keyboard**: Long-press text fields for on-screen keyboard (Plasma's own, included)
- **Wi-Fi**: System Settings → Connections → Wi-Fi
- **Bluetooth**: System Settings → Bluetooth

### System Updates

```bash
sudo pacman -Syu
```

The `batfix` kernel module will auto-rebuild after kernel upgrades (via pacman hook).

---

## Performance Notes

- **2GB RAM**: zram swap is pre-configured (compressed RAM-backed swap)
- **eMMC storage**: No swap to disk, reduces wear on slow storage
- **Bay Trail stability**: Kernel option `intel_idle.max_cstate=1` prevents CPU hangs in deep idle
- **Touch response**: Plasma Mobile optimized for tablet (no mouse/trackpad required)
- **Bluetooth**: AR3002 ROM-only (no firmware blob), instant after bthci powers it

---

## License & Attribution

### Files in this repository

- **build.sh** — Custom (free to modify)
- **Archiso profile** (profiledef.sh, packages.x86_64, airootfs structure) — Custom
- **install-venue.sh** — Custom orchestration of upstream fixes

### Files from ramonvanraaij/dell-venue-8-pro (fetched at build time)

The following are downloaded and integrated by `build.sh`:

- `etc/modprobe.d/` — BSD 3-Clause (Rúmon van Raaij)
- `etc/sysctl.d/` — BSD 3-Clause (Rúmon van Raaij)
- `etc/systemd/` — BSD 3-Clause (Rúmon van Raaij)
- `etc/NetworkManager/conf.d/` — BSD 3-Clause (Rúmon van Raaij)
- `etc/udev/rules.d/` — BSD 3-Clause (Rúmon van Raaij)
- `etc/pacman.d/hooks/` — BSD 3-Clause (Rúmon van Raaij)
- `etc/modules-load.d/` — BSD 3-Clause (Rúmon van Raaij)
- `usr/local/sbin/` (ath6kl-tune.sh, arch-launcher-icon.sh, venue-batfix-build.sh) — BSD 3-Clause (Rúmon van Raaij)
- `usr/local/src/venue-batfix/` (batfix.c, Makefile) — GPL-2.0 (Rúmon van Raaij, kprobe module)
- `acpi/bt0off.dsl` — BSD 3-Clause (Rúmon van Raaij)
- `src/bthci.c` — BSD 3-Clause (Rúmon van Raaij)

**All upstream files retain their original copyright headers and licensing.**

### Third-party components

- **Archiso** — [GPL-3.0+](https://gitlab.archlinux.org/archlinux/archiso/-/blob/master/LICENSE) — Arch Linux
- **Plasma Mobile** — [LGPL](https://invent.kde.org/plasma-mobile/) — KDE Project
- **systemd** — [LGPL-2.1+](https://github.com/systemd/systemd/blob/main/LICENSE) — systemd Project
- **Linux Kernel** — [GPL-2.0](https://www.kernel.org/doc/html/latest/process/license-rules.html) — Linux Kernel Project

---

## Support & References

### Original Hardware Fixes

- **GitHub**: https://github.com/ramonvanraaij/dell-venue-8-pro
- **Author**: [Rúmon van Raaij](https://github.com/ramonvanraaij)
- **Bluetooth deep-dive blog**: https://ramon.vanraaij.eu/the-bluetooth-that-was-never-dead-my-dell-venue-8-pro-baud-rate-journey/

### Plasma Mobile

- **Project**: https://invent.kde.org/plasma-mobile/
- **Documentation**: https://wiki.archlinux.org/title/KDE
- **Plasma 6**: https://www.kde.org/announcements/plasma/6/

### Arch Linux & archiso

- **Wiki**: https://wiki.archlinux.org/
- **Archiso**: https://wiki.archlinux.org/title/Archiso
- **Pacman**: https://wiki.archlinux.org/title/Pacman

---

**Built with ❤️ for the Dell Venue 8 Pro 5830 (and Arch Linux lovers everywhere)**

**Special thanks to [Rúmon van Raaij](https://github.com/ramonvanraaij) for the meticulous hardware research, reverse-engineering, and production-ready fixes.**