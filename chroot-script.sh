#!/bin/sh




disk=/dev/sdb
user=user

echo -e "\nEntering chroot!\n"


hwclock --systohc
ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime
locale-gen

echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'archiso' > /etc/hostname
echo 'KEYMAP=us' > /etc/vconsole.conf


pacman --needed -Sy grub efibootmgr os-prober arch-install-scripts

grub-install --target=i386-pc $disk --recheck
grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/ --removable


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

UUID_ROOT=$(blkid | grep $disk"2" | grep -o -P "(?<=UUID=\").*(?=\" UUID_SUB)")
grubby --update-kernel=ALL --args="resume=UUID=$UUID_ROOT"

sed -i '/zram0/d' /etc/fstab
sed -i 's/zstd:3/zstd:1/' /etc/fstab
[[ "$(cat /etc/fstab | grep /home/$user/.config)" ]] && echo "tmpfs    /home/$user/.cache    tmpfs   rw,nodev,nosuid,uid=$user,size=2G   0 0" > $mnt/etc/fstab
cat /etc/fstab

grub-mkconfig -o /boot/grub/grub.cfg


mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
Type=simple
ExecStart=
ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin $user --noclear %I 38400 linux
EOF

pacman -Sy iw iwd networkmanager sudo tar
#pacman -Sy dhcpcd

systemctl enable iwd.service NetworkManager.service 


# Default root password is: 123456
printf "123456\n123456\n" | passwd root

useradd -m $user -p 123456
usermod -aG wheel $user

su user

echo '

if [[ ! ${DISPLAY} && ${XDG_VTNR} == 1 ]]; then
   iwctl --passphrase 13FDC4A93E3C station wlan0 connect BELL364
   sudo pacman -Sy plasma-mobile dolphin kate btrfs-assistant ark pip lz4 mksh htop tar
fi' > /home/$user/.profile



echo "Exiting chroot!"
