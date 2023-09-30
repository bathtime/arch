#!/bin/sh



choose_disk () {


echo -e "\nDrives found:\n"

disks=$(fdisk -l | awk -F' |:' '/Disk \/dev\// { print $2 }')

for i in $disks; do
        size=$(fdisk -l | grep $i | awk -F' |:' '/Disk \/dev\// { print $4 }')
        printf "%s\t\t%sG\n" $i $size
done

disks+=$(echo -e "\nquit")

echo -e "\nWhich drive?\n"

select choice in $disks
do
   case $choice in
        quit) echo -e "\nQuitting!"; exit; ;;
        '')   echo -e "\nInvalid option!\n"; ;;
        *)    disk=$choice; echo; break; ;;
    esac
done

echo -e "\nSetup config:\n\ndisk: $disk, mounted on $mnt\nuser: $user\n"

}



delete_partitions () {

umount -n -R $mnt
sgdisk --zap-all $disk

sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk $disk
d

d

d

d

d

p
w
EOF

}



create_partitions () {

umount -n -R /mnt

sgdisk --zap-all $disk

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
p     # Print partitions 
w     # Write the changes
EOF


mkfs.fat -F 32 -n SYS $disk'1'
mkfs.btrfs -f -L ROOT $disk'2'

mkdir -p $mnt
mount $disk'2' $mnt

cd $mnt

btrfs subvolume create @
btrfs subvolume create @varcache
btrfs subvolume create @varlog
btrfs subvolume create @vartmp
btrfs subvolume create @snapshots
btrfs subvolume create @swap

cd /
umount -R $mnt


mount -o compress=zstd,noatime,subvol=@ $disk'2' $mnt

mkdir -p $mnt/{boot,etc,swap,tmp,var/{cache,log,tmp},.snapshots}

mount -o compress=zstd,noatime,subvol=@varlog $disk'2' $mnt/var/log
mount -o compress=zstd,noatime,subvol=@varcache $disk'2' $mnt/var/cache
mount -o compress=zstd,noatime,subvol=@vartmp $disk'2' $mnt/var/tmp
mount -o compress=zstd,noatime,subvol=@snapshots $disk'2' $mnt/.snapshots
mount -o compress=zstd,noatime,subvol=@swap $disk'2' $mnt/swap

# Make dirs nocow
chattr +C $mnt/var/log $mnt/var/cache $mnt/var/tmp $mnt/swap

# mount efi partition
mount --mkdir $disk'1' $mnt/boot


###  Make swap file  ###

btrfs filesystem mkswapfile --size 8G /mnt/swap/swapfile

# Can't be done in chroot for some reason
genfstab -U $mnt > mnt/etc/fstab

systemctl daemon-reload

}



install_pacstrap () {

#. /etc/profile
source /etc/profile
pacstrap -K $mnt base linux linux-firmware btrfs-progs vi

}



mount_mount () {

umount -R $mnt

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

}


unmount_mount () {

   umount -n -R /mnt

}



do_chroot () {

   echo -e "\nEntering chroot. Type 'exit' to leave."
   #arch-chroot $mnt
   arch-chroot /mnt bash -c 'export PS1="\n(chroot) # "; sh'
   echo -e "\nExiting chroot...\n"

}



chroot_install () {
 
   cp chroot-script.sh $mnt/bin/ 
   #arch-chroot $mnt /bin/chroot-script.sh $disk
   arch-chroot /mnt bash -c "export PS1='(chroot) # '; /bin/chroot-script.sh $disk"
} 



print_partitions () {

lsblk
blkid
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk $disk
p
q
EOF

}



mnt=/mnt
user=user

choose_disk

choices=(
"Choose disk"
"Partition disk"
"Install pacstrap"
"Chroot"
"Chroot install system"
"Mount $mnt"
"Unmount $mnt"
"Print partitions"
"Delete partitions"
"Quit"
)

select choice in "${choices[@]}" 
do

   case $choice in
        "Choose disk") choose_disk ;;
        "Partition disk") create_partitions ;;
        "Install pacstrap") install_pacstrap ;;
        "Chroot") do_chroot ;;
        "Chroot install system") chroot_install ;;
        "Mount $mnt") mount_mount  ;;
        "Unmount $mnt") unmount_mount  ;;
        "Print partitions") print_partitions ;;
        "Delete partitions") delete_partitions ;;
        "Quit") echo -e "\nQuitting!"; exit; ;;
        '')   echo -e "\nInvalid option!\n"; ;;
    esac
done





