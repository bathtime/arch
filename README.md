This program is in alpha! You're been warned.

# Run the script via:

Run live:
bash <(curl -sL https://bit.ly/a-install)

Copy to system and run:
curl -sL https://bit.ly/a-install > arch.sh && chmod +x arch.sh && ./arch.sh

# Features:

- Can be installed with Endeavour OS
- btrfs filesystem with suspend and hibernation option enabled
- USB installation option
- Run in tmpfs, squashfs, overlay, or snapshot mode
- Captures current firefox/chromium profile from host system
- Auto-setup installs full-featured OS in one command (kde, gnome, weston...)
- Copy/clone/sync/update to/from another system
- Error detection (set -e) activated

# Requirements:

- Arch linux (Must be run on an Arch-based system!)
- Internet

# Bugs:

- Ext4 and XFS file systems not correctly installing with bootloader
- No fully offline mode
- Sometimes will not unmount from /mnt after installation
