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

}



check_on_root () {

# Exit if device is mounted on /
if [[ $(mount | grep -E $disk".*on / type") ]]; then
	echo -e "\nDevice mounted on root. Will not run. Exiting.\n"
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

   if [[ "$(mount | grep 'on '$mnt)" ]]; then
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

check_on_root

unmount_disk

wipefs -a $disk 

# Not sure if this is required but can't hurt
echo "Wiping first 25mb of disk. Please be patient..."
dd if=/dev/zero of=$disk bs=1M count=25

}



create_partitions () {

check_on_root
delete_partitions

parted -s $disk mklabel gpt
parted -s --align=optimal $disk mkpart ESP fat32 1Mib 1000Mib 
parted -s $disk set 1 esp on
parted -s --align=optimal $disk mkpart BOOT fat32 1001Mib 1004Mib 
parted -s $disk set 2 bios_grub on
parted -s --align=optimal $disk mkpart SWAP linux-swap 1005Mib 10Gib
parted -s $disk set 3 swap on
parted -s --align=optimal $disk mkpart ROOT btrfs 10Gib 100%

mkfs.fat -F 32 -n EFI $disk'1'
mkfs.vfat -F 32 -n BIOS $disk'2'
mkswap $disk'3'
mkfs.btrfs -f -L ROOT $disk'4'

parted -s $disk print

echo -e "\nMounting $mnt..."
mount --mkdir $disk'4' $mnt

cd $mnt

btrfs subvolume create @
btrfs subvolume create @varcache
btrfs subvolume create @varlog
btrfs subvolume create @vartmp
#btrfs subvolume create @snapshots
#btrfs subvolume create @swap

unmount_disk

mount_mount


# Must be run here as cannot create UUIDs in chroot
genfstab -U $mnt > $mnt/etc/fstab

systemctl daemon-reload

}



mount_mount () {

check_on_root

if [[ $(mount | grep -E "on /mnt") ]]; then
   echo -e "\nDisk already mounted. Must unmount first. Exiting...\n"
   exit
fi

mount -o compress=zstd,noatime,subvol=@ $disk'4' $mnt

# Not sure if this is required
mkdir -p $mnt/{etc,tmp}

mount --mkdir -o compress=zstd,noatime,nodatacow,subvol=@varlog $disk'4' $mnt/var/log
mount --mkdir -o compress=zstd,noatime,nodatacow,subvol=@varcache $disk'4' $mnt/var/cache
mount --mkdir -o compress=zstd,noatime,nodatacow,subvol=@vartmp $disk'4' $mnt/var/tmp
#mount --mkdir -o compress=zstd,noatime,nodatacow,subvol=@snapshots $disk'4' $mnt/.snapshots
#mount --mkdir -o compress=zstd,noatime,nodatacow,subvol=@swap $disk'4' $mnt/swap

# Make dirs nocow
chattr -R +C $mnt/{var/{log,cache,tmp}}

# Or you'll get an error when packages try to install
chmod 1777 /mnt/var/tmp

# mount efi partition
mount --mkdir $disk'1' $mnt/efi

}



install_pacstrap () {

check_on_root

source /etc/profile
pacstrap -K $mnt base linux linux-firmware btrfs-progs vim libarchive

}

reset_keys () {

rm -rf /etc/pacman.d/gnupg
pacman-key --init
pacman-key --populate

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

   check_on_root
   copy_scripts   
   arch-chroot $mnt /chroot.sh $disk
} 



print_partitions () {

lsblk
blkid

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

# Make font big and readable
#pacman -S terminus-font
setfont ter-132b

if [[ ! "$1" = "" ]]; then
   disk=$1
else
   choose_disk
fi

check_viable_disk

echo -e "\nSetup config:\n\ndisk: $disk, mounted on $mnt\nuser: $user\n"

loadkeys en

# Update system clock
timedatectl

[[ "$(cat /sys/firmware/efi/fw_platform_size)" -eq 64 ]] && echo "This computer is running in uefi mode" || echo "This computer is not running in uefi mode."



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
"Reset pacman keys"
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
        "Reset pacman keys")    reset_keys ;;
	"Quit")			echo -e "\nQuitting!"; exit; ;;
        '')			echo -e "\nInvalid option!\n"; ;;
    esac
done
