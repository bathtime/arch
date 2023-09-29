#!/bin/sh

disks=/dev/sdb
mnt=/mnt


sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk $disk
d     # Delete partition

d     # Delete partition

d     # Delete partition

d     # Delete partition

d     # Delete partition

d     # Delete partition

n     # Add a new partition
p     # Partition number (Accept default: 1)
      # First sector (Accept default: varies)
      #
+1G   # Last sector (Accept default: varies)
t     # Type of filesystem
uefi  # Type of partition (EFI system partition)
n     # Add a new partition
      # Partition number (Accept default: 4)
      # Accept first sector
      # Accept last sector (Default: remaining space)
t     # Type of partition
      # Accept default
linux # Type of partition
p     # Printout partitions
w     # Write the changes
EOF



cd /
umount $mnt

mount -o compress=zstd,noatime,subvol=@ $disk'2' $mnt

mkdir -p $mnt/{boot,var/{log,cache,tmp},tmp,.snapshots}

mount -o compress=zstd,noatime,subvol=@varlog $disk'2' $mnt/var/log
mount -o compress=zstd,noatime,subvol=@varcache $disk'2' $mnt/var/cache
mount -o compress=zstd,noatime,subvol=@vartmp $disk'2' $mnt/var/tmp
mount -o compress=zstd,noatime,subvol=@snapshots $disk'2' $mnt/.snapshots

# Make dirs nocow
chattr +C $mnt/var/log $mnt/var/cache $mnt/var/tmp


# mount efi partition
mount --mkdir $disk'1' $mnt/boot

echo 'en_US.UTF-8 UTF-8' > $mnt/etc/locale.gen  
echo 'en_US ISO-8859-1' >> $mnt/etc/locale.gen

pacstrap -K $mnt base linux linux-firmware btrfs-progs vim




