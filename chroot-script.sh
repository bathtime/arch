export PS1="(chroot) $PS1"

ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime

hwclock --systohc

locale-gen

echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'archiso' > /etc/hostname
echo 'KEYMAP=us' > /etc/vconsole.conf

printf "123456\n123456\n" | passwd root

ls -la /

pacman -S grub efibootmgr os-prober

grub-mkconfig -o /boot/grub/grub.cfg

grub-install --target=i386-efi --efi-directory=/boot/ --bootloader-id=GRUB

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
Type=simple
ExecStart=
ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin user --noclear %I 38400 linux
EOF

useradd -m user -p 123456
usermod -aG wheel user

su user

echo '
if [[ ! ${DISPLAY} && ${XDG_VTNR} == 1 ]]; then
   #startplasma-wayland
   echo 'Autologin.'
fi' >> ~/.profile


echo -e '\nEntering personal bash. Type 'exit' to exit chroot\n'
bash
echo -e '\nExiting chroot.\n'

#Shouldn't be required as was run with pacstrap
#mkinitcpio -P










