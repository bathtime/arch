#!/bin/sh

user=user

# Must be run as user to properly install pip, yay, and flatpak 
if [[ "$(id -u)" -ne 0 ]]; then
   echo "This script must be run as root. Exiting."
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
   sudo -u $user iwctl --passphrase 13FDC4A93E3C station wlan0 connect BELL364
fi

if [[ ! "$(echo $interfaces | grep eno1)" ]]; then

   # Helps with slow booting caused by waiting for a connection
   mkdir -p /etc/systemd/system/dhcpcd@.service.d/
   cat > '/etc/systemd/system/dhcpcd@.service.d/no-wait.conf' << EOF
      [Service]
      ExecStart=
      ExecStart=/usr/bin/dhcpcd -b -q %I
EOF

   systemctl disable dhcpcd.service
   systemctl enable dhcpcd@eno1.service
fi

timedatectl set-ntp yes



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

[[ ! "$(cat /etc/fstab | grep '/swap/swapfile')" ]] && echo -e "\n/swap/swapfile none swap defaults 0 0\n" >> /etc/fstab

swapon /swap/swapfile

# To hibernate
#echo disk > /sys/power/state
#echo freeze > /sys/power/state
#echo mem > /sys/power/state
#echo s2idle > /sys/power/mem_sleep
#echo deep > /sys/power/mem_sleep



# lz4 kernel compression (for speed)
pacman -S lz4
cat > /etc/mkinitcpio.conf.d/lz4.conf << EOF
COMPRESSION="lz4"
MODULES_DECOMPRESS="yes"
EOF


# Add 'resume' hook to allow for hibernation
cat > /etc/mkinitcpio.conf.d/myhooks.conf << EOF
HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems resume fsck)
EOF

mkinitcpio -P


pacman -S --needed git base-devel less


# Install yay
sudo -u $user git clone https://aur.archlinux.org/yay-bin
cd yay-bin
sudo -u $user makepkg -si

# To be run at first use:
sudo -u $user yay -Y --gendb

# To check for development package updates
# sudo -u $user yay -Syu --devel

# To make development package updates permanently enabled
# sudo -u $user yay -Syu


pacman -S plasma-desktop plasma-wayland-session plasma-pa pipewire-pulse kscreen snapper dolphin konsole kate ark firefox

sudo -u $user yay plasma-mobile btrfs-assistant bauh




###  Snapper  ### 

umount /.snapshots
rm -rf /.snapshots
snapper create-config /
btrfs subvolume create /.snapshots

# Create the first snapshot as read only (-r)
btrfs subvolume snapshot -r / /.snapshots/'Setup complete'
btrfs subvolume list /



#if [[ $(snapper list | awk "/Setup complete/") == "" ]]; then
#   snapper -c root create --description "Setup complete"
#fi
  
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

#chattr +C /home/user/.cache

su - user

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

sudo -u $user pip3 install epy-reader

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







###  flatpaks script (will not work in chroot)  ###
 
cat > ~/.local/bin/flatpack-install.sh << EOF
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flathub org.mozilla.firefox
flatpak install flathub rocks.koreader.KOReader
 
# If you run into issues this might help
#flatpak uninstall --unused
EOF
chmod +x ~/.local/bin/flatpack-install.sh
 

