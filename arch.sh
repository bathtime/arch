#!/bin/bash


check_viable_disk () {

if [[ "$disk" == "" ]]; then
   echo -e "\nMissing disk parameter. Exiting.\n"
   exit
fi

if [[ ! "$(lsblk --output=PATH -d -n | grep $disk)" ]]; then
   echo -e "\nNo such disk found ($disk). Exiting.\n"
   exit
fi

# Exit if device is mounted on /
if [[ ! $(mount | grep -E $disk".*on $mnt") ]]; then
   echo -e "\nDevice not mounted on $mnt. Will not run this script. Exiting.\n"
   exit
fi

}



unmount_disk () {

if [[ "$(mount | grep $mnt)" ]]; then

   echo "Unmounting $mnt..."

   # Shouldn't be in directory we're unmounting   
   [[ "$(pwd | grep $mnt)" ]] && cd ..

   sync

   umount -n -R $mnt

   if [[ "$(pwd | grep $mnt)" ]]; then
      echo "Couldn't unmount. Trying alternative method. Please be patient..." 
      sync
      sleep 2
      umount -R -l $mnt
   fi 

   if [[ "$?" -eq 0 ]]; then
      echo "Unmount successful."
   else
      echo "ERROR ($?): could not unmount!"
      exit
   fi 

else
   echo "Disk already unmounted!"
fi

}



choose_disk () {


echo -e "\nDrives found:\n"

lsblk --output=PATH,SIZE,MODEL,TRAN -d
disks="$(lsblk --output=PATH -d -n)"

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

unmount_disk

# Not sure which one is the best to use
#sgdisk --zap-all $disk
#sfdisk --delete $disk
wipefs -a $disk 

# Not sure if this is required but can't hurt
echo "Wiping first 100mb of disk. Please be patient..."
dd if=/dev/zero of=$disk bs=1M count=100

}



create_partitions () {


delete_partitions

#parted -s $disk mklabel msdos
#parted -s $disk mkpart primary 1MiB 1025MiB
#parted -s $disk align-check optimal 1

#parted -s $disk mklabel gptklabel gpt
#parted -s $disk set 1 boot on
#parted -s $disk mkpart primary fat32 1MiB 1000MiB
#mkfs.fat -F 32 -n SYS $disk'1'
#mkfs.btrfs -f -L ROOT $disk'2'



echo "Wiping first 100mb of disk. Please be patient..."
dd if=/dev/zero of=/dev/sdb bs=1M count=100

parted -s $disk mklabel gpt
parted -s --align=optimal $disk mkpart ESP fat32 1MiB 1Gib 
parted -s $disk set 1 esp on
#parted -s $disk set 1 bios_grub on
parted -s --align=optimal $disk mkpart btrfs 1Gib 100%
 
#mkfs.fat -F 32 -n SYS $disk'1'
mkfs.vfat -n EFI $disk'1' 
mkfs.btrfs -f -L ROOT $disk'2'

parted -s $disk print


mount_mount


###  Make swap file  ###

btrfs filesystem mkswapfile --size 8G $mnt/swap/swapfile

# Must be run here as cannot create UUIDs in chroot
genfstab -U $mnt > $mnt/etc/fstab

systemctl daemon-reload

}



mount_mount () {

echo -e "\nMounting $mnt..."
mount --mkdir $disk'2' $mnt

cd $mnt

btrfs subvolume create @
btrfs subvolume create @varcache
btrfs subvolume create @varlog
btrfs subvolume create @vartmp
btrfs subvolume create @snapshots
btrfs subvolume create @swap

cd .. 
unmount_disk

mount -o compress=zstd,noatime,subvol=@ $disk'2' $mnt

# Not sure if this is required
mkdir -p $mnt/{etc,tmp}

mount --mkdir -o compress=zstd,noatime,subvol=@varlog $disk'2' $mnt/var/log
mount --mkdir -o compress=zstd,noatime,subvol=@varcache $disk'2' $mnt/var/cache
mount --mkdir -o compress=zstd,noatime,subvol=@vartmp $disk'2' $mnt/var/tmp
mount --mkdir -o compress=zstd,noatime,subvol=@snapshots $disk'2' $mnt/.snapshots
mount --mkdir -o compress=zstd,noatime,subvol=@swap $disk'2' $mnt/swap

# Make dirs nocow
chattr +C $mnt/{swap,var/{log,cache,tmp}}

# mount efi partition
mount --mkdir $disk'1' $mnt/boot

}



install_pacstrap () {


#warning: directory permissions differ on /mnt/var/tmp/
#filesystem: 755  package: 1777

#bsdtar: Failed to set default locale

#. /etc/profile
#source /etc/profile
pacstrap -K $mnt base linux linux-firmware btrfs-progs vi libarchive

}



copy_scripts () {

echo -e "\nCopying scripts to $mnt\n"
cp {arch.sh,chroot.sh,post-setup.sh} $mnt

}



do_chroot () {

echo -e "\nEntering chroot. Type 'exit' to leave.\n"

arch-chroot $mnt /bin/bash -ic 'exec env PS1="(chroot) # " bash --norc'

echo -e "\nExiting chroot...\n"

}



chroot_install () {
   arch-chroot $mnt /chroot.sh $disk
} 



print_partitions () {

lsblk
blkid
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk $disk
p
q
EOF

}



connect_wireless () {

echo -e "\nAttempting to connect to wireless...\n"
iwctl --passphrase 13FDC4A93E3C station wlan0 connect BELL364

if [[ "$?" -eq 0 ]]; then
   echo "Connection successful!"
else
   echo "Connection unsuccessful."
fi

}



post_setup () {

echo TODO

}



download_scripts () {

echo -e "\nDowloading scripts from Github..."

#curl -s https://raw.githubusercontent.com/bathtime/arch/main/arch.sh > arch.sh
curl -s https://raw.githubusercontent.com/bathtime/arch/main/chroot.sh > chroot.sh
curl -s https://raw.githubusercontent.com/bathtime/arch/main/post-setup.sh > post-setup.sh

if [[ "$?" -eq 0 ]]; then
   echo "Download successful!"
   chmod +x arch.sh chroot.sh post-setup.sh
else
   echo "Download unsuccessful."
fi

}



download_apps () {

pacman -S arch-install-scripts 

}



mnt=/mnt
user=user


if [[ ! "$1" = "" ]]; then
   disk=$1
else
   choose_disk
fi

check_viable_disk

echo -e "\nSetup config:\n\ndisk: $disk, mounted on $mnt\nuser: $user\n"


while [[ "${1}" != "" ]]; do
        case "${1}" in
        -c|--copy)      copy_scripts     ; exit ;;
        -d|--download)  download_scripts ; exit ;;
        -a|--apps)      download_apps    ; exit ;;
        -p|--post)      post_setup       ; exit ;;
        -w|--wireless)  connect_wireless ; exit ;;
    esac
    
    shift 1
done


choices=(
"Choose disk"
"Partition disk"
"Install pacstrap"
"Copy scripts"
"Chroot install"
"Chroot"
"Mount $mnt"
"Unmount $mnt"
"Print partitions"
"Delete partitions"
"Connect wireless"
"Download scripts"
"Download apps"
"Post setup"
"Quit"
)


select choice in "${choices[@]}" 
do
   case $choice in
        "Choose disk")		choose_disk ;;
        "Partition disk")	create_partitions ;;
        "Install pacstrap")	install_pacstrap ;;
        "Chroot")		do_chroot ;;
        "Chroot install")	chroot_install ;;
        "Mount $mnt")		mount_mount  ;;
        "Unmount $mnt")		unmount_disk  ;;
        "Print partitions")	print_partitions ;;
        "Delete partitions")	delete_partitions ;;
        "Copy scripts")		copy_scripts ;;
        "Connect wireless")	connect_wireless ;;
        "Download scripts")	download_scripts ;;
        "Download apps")	download_apps    ;;
        "Post setup")		post_setup ;;
        "Quit")			echo -e "\nQuitting!"; exit; ;;
        '')			echo -e "\nInvalid option!\n"; ;;
    esac
done


exit

loadkeys en

pacman -S terminus-font
setfont ter-132b

# 64 = verification that computer is running in uefi mode
cat /sys/firmware/efi/fw_platform_size

timedatectl

