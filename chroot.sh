#!/bin/sh


disk=/dev/sdb
mnt=/mnt

cd /
umount -R $mnt

mount -o compress=zstd,noatime,subvol=@ $disk'2' $mnt

#mkdir -p $mnt/{boot,var/{log,cache,tmp},tmp,.snapshots}

mount -o compress=zstd,noatime,subvol=@varlog $disk'2' $mnt/var/log
mount -o compress=zstd,noatime,subvol=@varcache $disk'2' $mnt/var/cache
mount -o compress=zstd,noatime,subvol=@vartmp $disk'2' $mnt/var/tmp
mount -o compress=zstd,noatime,subvol=@snapshots $disk'2' $mnt/.snapshots


# mount efi partition
mount  $disk'1' $mnt/boot


arch-chroot $mnt

