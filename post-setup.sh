#!/bin/sh

iwctl --passphrase 13FDC4A93E3C station wlan0 connect BELL364


sudo pacman -S --needed git base-devel less


# Install yay
git clone https://aur.archlinux.org/yay-bin
cd yay-bin
makepkg -si

# To be run at first use:
yay -Y --gendb

# To check for development package updates
# yay -Syu --devel

# To make development package updates permanently enabled
# yay -Syu



sudo pacman -S plasma-desktop plasma-wayland-session snapper kscreen dolphin konsole kate ark firefox

yay plasma-mobile btrfs-assistant bauh


###  Snapper  ###


yay plasma-mobile plasma-wayland-session btrfs-assistant bauh

sudo pacman -S dolphin konsole kate ark firefox



###  Snapper  ### 

umount /.snapshots
rm -rf /.snapshots
btrfs subvolume create /.snapshots
snapper create-config /
 
if [[ $(snapper list | awk "/Setup complete/") == "" ]]; then
   snapper -c root create --description "Setup complete"
fi
  
# Automate snapper and btrfs services  ###
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer
systemctl enable snapper-boot.timer
 
systemctl enable btrfs-balance.timer
systemctl enable btrfs-scrub.timer
systemctl enable btrfs-trim.timer
 
# Have snapper take a snapshot every 20 mins (default is every 1hr)
mkdir -p /etc/systemd/system/snapper-timeline.timer.d/
cat > /etc/systemd/system/snapper-timeline.timer.d/frequency.conf << EOF
[Timer]
OnCalendar=
OnCalendar=*:0/20
EOF

echo "To edit snapper config, run: vi /etc/snapper/configs/root"



