#!/bin/bash

set -e

version='6.5.6'

cd /home/user/build/linux/src/linux-"$version"

make mrproper

if [ -f '/home/user/.local/bin/.config' ]; then
   echo "Copying kernel from .local/bin..."
   cp /home/user/.local/bin/.config . 
else
   [ ! -f '.config' ] && zcat /proc/config.gz > '.config'
fi


zcat /proc/config.gz > '.config'

make nconfig

cp .config /home/user/.local/bin/

make -j6

make modules

sudo make modules_install

sudo cp /home/user/build/linux/src/linux-"$version"/arch/x86_64/boot/bzImage /boot/vmlinuz-linux-custom

sudo cp /etc/mkinitcpio.d/linux.preset /etc/mkinitcpio.d/linux-custom.preset

sudo mkinitcpio -k "$version"-arch2-1-custom -g /boot/initramfs-linux-custom.img

grub-mkconfig -o /boot/grub/grub.cfg

echo "Finished!!"




