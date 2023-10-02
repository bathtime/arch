 #!/bin/sh


disk=$1
user=user

if [[ "$disk" == "" ]]; then
   echo -e "\nMissing disk parameter. Exiting.\n"
   exit
fi

if [[ ! "$(lsblk --output=PATH -d -n | grep $disk)" ]]; then
   echo -e "\nNo such disk found ($disk). Exiting.\n"
   exit
fi

# Exit if device is not mounted (or we're probably using a disk we shouldn't be using)
if [[ ! $(mount | grep -v -G $disk".*on /mnt") ]]; then
   echo -e "\nMust be mounted on $mnt. Will not run this script. Exiting.\n"
   exit
fi


source /etc/profile

echo -e 'en_US.UTF-8 UTF-8\nen_US ISO-8859-1' > /etc/locale.gen  

hwclock --systohc
ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime

echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'arch' > /etc/hostname
echo 'KEYMAP=us' > /etc/vconsole.conf
echo 'FONT=ter-132b' > /etc/vconsole.conf   # Set to biggest tty font (requires terminus-font package installed)
locale-gen



pacman --needed -Sy grub efibootmgr os-prober arch-install-scripts sudo tar terminus-font libarchive man
pacman --needed -S dosfstools parted

###  Grub and partitions  ###

#grub-install --target=i386-pc $disk --recheck

#Installing for i386-pc platform.
#grub-install: warning: this GPT partition label contains no BIOS Boot Partition; embedding won't be possible.
#grub-install: warning: Embedding is not possible.  GRUB can only be installed in this setup by using blocklists.  However, blocklists are UNRELIABLE and their use is discouraged..
#grub-install: error: will not proceed with blocklists.



grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/ --removable
# grub-install: error: unknown filesystem.  # When only grub-bois flag set
#Installing for x86_64-efi platform. 
#Installation finished. No error reported. 


cat > /etc/default/grub << EOF

GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=""
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="quiet nmi_watchdog=0 loglevel=3 systemd.show_status=auto rd.udev.log_level=3"
GRUB_DISABLE_RECOVERY="true"
#GRUB_ENABLE_BLSCFG=true
GRUB_HIDDEN_TIMEOUT=2
GRUB_RECORDFAIL_TIMEOUT=1
GRUB_TIMEOUT=0
 
# Update grub with:
# grub-mkconfig -o /boot/grub/grub.cfg

EOF

# Don't need
sed -i '/zram0/d' /etc/fstab

# Changing compression
sed -i 's/zstd:3/zstd:1/' /etc/fstab

# genfstab will generate a swap drive. we're using a swap file instead
sed -i '/LABEL=SWAP/d; /none.*swap.*defaults/d' /etc/fstab

# Put ~/.cache in tmpfs
[[ ! "$(cat /etc/fstab | grep /home/$user/.config)" ]] && echo "tmpfs    /home/$user/.cache    tmpfs   rw,nodev,nosuid,uid=$user,size=2G   0 0" >> /etc/fstab

cat /etc/fstab

grub-mkconfig -o /boot/grub/grub.cfg



# Autologin to tty1

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
Type=simple
ExecStart=
ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin $user --noclear %I 38400 linux
EOF



###  Setup network  ###

pacman -Sy iw iwd dhcpcd

# Helps with slow booting caused by waiting for a connection
mkdir -p /etc/systemd/system/dhcpcd@.service.d/
cat > /etc/systemd/system/dhcpcd@.service.d/no-wait.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dhcpcd -b -q %I
EOF

mkdir -p /etc/iwd
cat > /etc/iwd/main.conf << EOF
[General]
EnableNetworkConfiguration=true
EOF

# So iwd can automatically connect without any further interaction
mkdir -p /var/lib/iwd
cat > /var/lib/iwd/BELL364.psk << EOF
[Security]
Passphrase=13FDC4A93E3C
EOF

echo "Enabling network services..."
systemctl enable iwd.service dhcpcd.service





###  Setup sudo and user  ###

mkdir -p /etc/sudoers.d
echo "$user ALL=(ALL)  NOPASSWD: /usr/bin/btrfs-assistant" > /etc/sudoers.d/nopasswd
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel

# Default root password is: 123456
printf "123456\n123456\n" | passwd root

useradd -m $user -p '123456'
usermod -aG wheel $user

printf "123456\n123456\n" | passwd $user 



###  Finish setting up user  ###

su - user

echo '# If running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi
 
PATH="$HOME/.local/bin:$PATH"
 
export EDITOR=/usr/bin/vi
export QT_QPA_PLATFORM=wayland
export QT_IM_MODULE=Maliit
export MOZ_ENABLE_WAYLAND=1
export XDG_RUNTIME_DIR=/run/$USER/1000
export RUNLEVEL=3
export QT_LOGGING_RULES="*=false"

if [[ ! ${DISPLAY} && ${XDG_VTNR} == 1 ]]; then
   iwctl --passphrase 13FDC4A93E3C station wlan0 connect BELL364
fi' > /home/$user/.bash_profile
#chmod +x /home/$user/.bash_profile

touch /home/$user/.hushlogin


echo -e "\nExiting chroot!\n"




