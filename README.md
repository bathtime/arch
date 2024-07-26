This program is in alpha!


# Run the script:

Live:

bash <(curl -sL https://bit.ly/a-install)

Copy to system:

curl -sL https://bit.ly/a-install > arch.sh && chmod +x arch.sh && ./arch.sh

# Features:

- btrfs filesystem with suspend and hibernation option enabled
- USB installation option
- Run in tmpfs, squashfs, overlay, or snapshot mode
- Captures current firefox/chromium profile from host system
- Auto-setup installs full-featured OS in one command (kde, gnome, weston...)
- Copy/clone/sync/update to/from another system
- Error detection (set -e) activated

# Requirements:

- Arch linux or Arch-based distro (Only Endeavour OS tested)
- Internet

# Bugs:

- Ext4 and XFS file systems not correctly installing with bootloader
- No offline mode
- Issues with unmounting after invoking chroot



- 
