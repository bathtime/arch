This program is in alpha!


# Run the script:

Live:

bash <(curl -sL https://bit.ly/a-install)

Copy to system:

curl -sL https://bit.ly/a-install > arch.sh && chmod +x arch.sh && ./arch.sh

# Features:

- Supported filesystems: ext4, btrfs, xfs, jfs, nilfs2, f2fs (TODO: bcachefs)
- suspend and hibernation option enabled
- USB installation option
- Boot root system into tmpfs, squashfs, overlay, or snapshot mode
- Captures current firefox/chromium profile from host system
- Auto-setup installs full-featured OS in one command (kde, gnome, weston...)
- Copy/clone/sync/update to/from another system
- Error detection (set -e) activated (TODO: verification)

# Requirements:

- Internet
- Arch linux or Arch-based distro (Only Endeavour OS tested)

# Bugs:

- Only grub bootloader is working
- No offline mode
- Issues with unmounting after partitioning
- Resume error on USB devices
