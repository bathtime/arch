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

grub-mkconfig > /boot/grub/grub.cfg
grub-install --target=i386-efi --efi-directory=/boot/ --bootloader-id=GRUB


echo -e '\nEntering personal bash. Type 'exit' to exit chroot\n'
bash
echo -e '\nExiting chroot.\n'

#Shouldn't be required as was run with pacstrap
#mkinitcpio -P
