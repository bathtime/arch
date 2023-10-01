#!/bin/sh



# Must be run as user to properly install pip, yay, and flatpak 
if [[ "$(id -u)" -eq 0 ]]; then
   echo "You're running in root. This script must be run as user. Exiting."
   exit
fi


interfaces="$(ls /sys/class/net | sed -E '/lo/d')"

echo -e "\nAvailable interfaces:\n$interfaces"

if [[ ! "$(echo $interfaces | grep wlan0)" ]]; then
   echo "No wireless interfaces found. Removing wireless applications..."
   #sudo pacman -R iw iwd
   systemctl disable iwd.service
else
   echo "Wireless interface found. Attempting connection..."
   iwctl --passphrase 13FDC4A93E3C station wlan0 connect BELL364
fi

if [[ ! "$(echo $interfaces | grep eth0)" ]]; then
   sudo systemctl disable dhcpcd.service
   sudo systemctl enable dhcpcd@eth0.service
fi

sudo timedatectl set-ntp yes



###  Make btrfs swap file  ###

# Swap file must be on a separate subvolume if running btrfs
if [[ ! "$(btrfs subvolume list / | grep /swap)" ]]; then
   btrfs subvolume create /swap
   chattr +C /swap
fi

btrfs filesystem mkswapfile --size 8G /swap/swapfile

disk=$(mount | grep 'on / ' | awk '{ print $1 }')
UUID_ROOT=$(blkid -s UUID -o value $disk)
offset=$(btrfs inspect-internal map-swapfile -r /swap/swapfile)

sed -i "s/GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"resume=UUID=$UUID_ROOT resume_offset=$offset /g" /etc/default/grub

[[ ! "$(cat /etc/fstab | grep '/swap/swapfile')" ]] && echo -e "\n/swap/swapfile none swap defaults 0 0" >> /etc/fstab







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


sudo pacman -S plasma-desktop plasma-wayland-session plasma-pa pipewire-pulse kscreen snapper dolphin konsole kate ark firefox

yay plasma-mobile btrfs-assistant bauh




###  Snapper  ### 

umount /.snapshots
rm -rf /.snapshots
snapper create-config /
btrfs subvolume create /.snapshots
 
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


###  Setup konsole profiles  ###

mkdir -p ~/.local/share/konsole
cat > ~/.local/share/konsole/epy.profile << EOF
[Appearance]
ColorScheme=WhiteOnBlack
Font=Noto Sans Mono,24,-1,5,50,0,0,0,0,0
 
[General]
Name=epy
Parent=FALLBACK/
 
[Scrolling]
ScrollBarPosition=2
EOF
 
cat > ~/.local/share/konsole/user.profile << EOF
[Appearance]
ColorScheme=WhiteOnBlack
Font=Noto Sans Mono,14,-1,5,50,0,0,0,0,0
 
[General]
Name=user
Parent=FALLBACK/
EOF



# Create .desktop file

mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/btrfs-assistant.desktop << EOF
[Desktop Entry]
Name=Btrfs Assistant
Comment=Change system settings
Exec=sudo /usr/bin/btrfs-assistant
Terminal=false
Type=Application
Icon=btrfs-assistant
Categories=System
NoDisplay=false
EOF


 
###  Epy reader  ###

pip3 install epy-reader

cat > ~/.local/share/applications/epy.desktop << EOF
[Desktop Entry]
Categories=System
Comment=Read ebooks
Exec=konsole --profile epy -e 'epy %u'
Icon=audiobook
Name=Epy
NoDisplay=false
Path=
StartupNotify=true
Terminal=false
TerminalOptions=
Type=Application
X-KDE-SubstituteUID=false
X-KDE-Username=
EOF
 
#sed -i 's/    "MouseSupport": false,/    "MouseSupport": true,/g' ~/.config/epy/configuration.json


cat > ~/.local/share/applications/btrfsi-assistant.desktop << EOF
[Desktop Entry]
Name=Btrfs Assistant
Comment=Change system settings
Exec=sudo /usr/bin/btrfs-assistant
Terminal=false
Type=Application
Icon=btrfs-assistant
Categories=System
NoDisplay=false
EOF


cat > ~/.config/kwinrulesrc << EOF
[$Version]
update_info=kwinrules.upd:replace-placement-string-to-enum,kwinrules.upd:use-virtual-desktop-ids

[1]
Description=Windows
maximizehoriz=true
maximizehorizrule=6
maximizevert=true
maximizevertrule=6
noborder=true
noborderrule=6
types=1

[General] 
count=1 
rules=1 
EOF


# Get rid of cruft
systemctl disable avahi-daemon.service bluetooth.service firewalld ModemManager.service NetworkManager.service

#chattr +C /home/user/.cache




###  flatpaks script (will not work in chroot)  ###
 
cat > ~/.local/bin/flatpack-install.sh << EOF
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flathub org.mozilla.firefox
flatpak install flathub rocks.koreader.KOReader
 
# If you run into issues this might help
#flatpak uninstall --unused
EOF
chmod +x ~/.local/bin/flatpack-install.sh
 

