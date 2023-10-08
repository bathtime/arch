#!/bin/bash


# So systemd won't remount with 'rw' after we put 'ro' for kernel params 
if [ ! "$(systemctl --all | awk '/systemd-remount-fs.service/ && /masked/')" ]; then
   sudo systemctl mask systemd-remount-fs.service
fi

# Check if root fs is mounted as readonly. If so, these dirs need to be mutable
if [ "$(mount | awk '/on \/ / && /ro/')" ] || [ "$1" = '-a' ]; then

sudo mount -o uid=user -t tmpfs tmpfs /home/user/.config
sudo mount -o uid=user -t tmpfs tmpfs /home/user/.local
sudo mount -o uid=user -t tmpfs tmpfs /home/user/.mozilla

mkdir -p /home/user/.local/{bin,share,share/baloo} /home/user/.config/kdedefaults

tar xvf /home/user/setup.tar

fi



