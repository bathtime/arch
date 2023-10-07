#!/bin/bash


# Run with:
# bash <(curl -sL bit.ly/a-install)


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
  
if [[ $(mount | grep -G "$disk.*on / type") ]]; then 
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

lsblk --output=PATH,SIZE,MODEL,TRAN -d | grep -P "/dev/sd|nvme|vd"
disks=$(lsblk -dpnoNAME|grep -P "/dev/sd|nvme|vd") 
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

echo -e "\nWiping disk...\n"

wipefs -af $disk 
sgdisk -Zo $disk

# Not sure if this is required but can't hurt
echo "Wiping first 25mb of disk. Please be patient..."
dd if=/dev/zero of=$disk bs=1M count=25

}



create_partitions () {

check_on_root
delete_partitions

parted -s $disk mklabel gpt
parted -s --align=optimal $disk mkpart ESP fat32 1Mib 1000Mib 
parted -s $disk set $efiPart esp on

#parted -s --align=optimal $disk mkpart BOOT ext4 1001Mib 2000Mib
#parted -s --align=optimal $disk mkpart BOOT fat32 1001Mib 1004Mib 
#parted -s $disk set 2 bios_grub on

parted -s --align=optimal $disk mkpart SWAP linux-swap 1005Mib 10Gib
parted -s $disk set $swapPart swap on
parted -s --align=optimal $disk mkpart ROOT btrfs 10Gib 100%


if [ "$encrypt" -eq 1 ]; then

   ESP=/dev/disk/by-partlabel/ESP
   ROOT=/dev/disk/by-partlabel/CRYPTROOT
   BTRFS="/dev/mapper/cryptroot"

   partprobe $disk

   echo -n "$password" | cryptsetup luksFormat "$ROOT" -d -
   echo -n "$password" | cryptsetup open "$ROOT" cryptroot -d - 

else

   ESP=$disk$efiPart
   ROOT=$disk$rootPart
   BTRFS=$ROOT

fi


mkfs.fat -F 32 -n EFI $ESP
mkswap $disk$swapPart
mkfs.btrfs -f -L ROOT $BTRFS

parted -s $disk print

echo -e "\nMounting $mnt..."
mount --mkdir $BTRFS $mnt

cd $mnt

for subvol in '' "${subvols[@]}"; do
    btrfs su cr /mnt/@"$subvol"
done

mkdir -p $mnt/{etc,tmp}

unmount_disk
mount_mount

}



mount_mount () {

check_on_root

if [[ ! $(mount | grep -E "on /mnt") ]]; then

if [ "$encrypt" -eq 1 ]; then

   ESP=/dev/disk/by-partlabel/ESP
   ROOT=/dev/disk/by-partlabel/CRYPTROOT
   BTRFS="/dev/mapper/cryptroot"

else

   ESP=$disk$efiPart
   ROOT=$disk$rootPart
   BTRFS=$ROOT

fi

mountopts="noatime,compress-force=zstd:1,discard=async"


echo -e "\nMounting...\n"
for subvol in '' "${subvols[@]}"; do
    mount --mkdir -o "$mountopts",subvol=@"$subvol" $BTRFS $mnt/"${subvol//_//}"
    echo "mount -o $mountopts,subvol=@$subvol $BTRFS /mnt/${subvol//_//}"
done

mkdir -p $mnt/{etc,tmp}

# mount efi partition
mount --mkdir $ESP $mnt/efi

# Make dirs nocow
chattr -R +C $mnt/var/{cache,log,tmp}

#chmod 750 $mnt/root

# Or you'll get an error when packages try to install
chmod 1777 $mnt/var/tmp

# mount efi partition
mount --mkdir $ESP $mnt/efi

fi

}



install_pacstrap () {

check_on_root

source /etc/profile
pacstrap -K $mnt base linux linux-firmware btrfs-progs vim vi libarchive intel-ucode

}



install_EFISTUB () {

echo

}



install_GRUB () {

pacstrap -K $mnt grub grub-btrfs os-prober efibootmgr inotify-tools lz4

SWAP_UUID=$(blkid -s UUID -o value $disk$swapPart)


arch-chroot $mnt /bin/bash -e << EOF

#grub-install --target=i386-pc $disk --recheck
grub-install --target=x86_64-efi --efi-directory=/efi/ --bootloader-id=GRUB --removable

cat > /etc/default/grub << EOF2

GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=""
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="quiet nmi_watchdog=0 loglevel=3 rd.udev.log_level=3 resume=UUID=$SWAP_UUID zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=20 zswap.zpool=z3fold $extra_cmd"
GRUB_DISABLE_RECOVERY="true"
GRUB_HIDDEN_TIMEOUT=2
GRUB_RECORDFAIL_TIMEOUT=1
GRUB_TIMEOUT=0
 
# Update grub with:
# grub-mkconfig -o /boot/grub/grub.cfg

EOF2


if [ "$encrypt" -eq 1 ]; then

   ENCRYPT_UUID=$(blkid -s UUID -o value $ROOT)
   sed -i "\,^GRUB_CMDLINE_LINUX=\"\",s,\",&rd.luks.name=$ENCRYPT_UUID=cryptroot root=$BTRFS," $mnt/etc/default/grub

fi


# Allows grub to run snapshots
systemctl enable grub-btrfsd.service
/etc/grub.d/41_snapshots-btrfs

# Remove grub os-prober message
sed -i 's/grub_warn/#grub_warn/g' /etc/grub.d/30_os-prober


grub-mkconfig -o /boot/grub/grub.cfg

EOF

}



setup_fstab () {

genfstab -U $mnt > $mnt/etc/fstab


###  Tweak the resulting /etc/fstab generated  ###

SWAP_UUID=$(blkid -s UUID -o value $disk$swapPart)

# No zram 
#sed -i '/zram0/d' $mnt/etc/fstab

# Changing compression
sed -i 's/zstd:3/zstd:1/' $mnt/etc/fstab

# genfstab will generate a swap drive. we're using a swap file instead
sed -i '/LABEL=SWAP/d; /none.*swap.*defaults/d' $mnt/etc/fstab

#echo '/dev/zram0 none swap defaults,pri=100 0 0' >> /etc/fstab

[ ! "$(cat $mnt/etc/fstab | grep 'none swap defaults 0 0')" ] && echo "UUID=$SWAP_UUID none swap defaults 0 0" >> $mnt/etc/fstab

# Put ~/.cache in tmpfs
[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /home/')" ] && echo -e "tmpfs    /home/$user/.cache    tmpfs   rw,nodev,nosuid,uid=$user,size=2G   0 0" >> $mnt/etc/fstab

systemctl daemon-reload

cat $mnt/etc/fstab

# At this point you could log into your system 
#arch-chroot $mnt printf "123455\n123456\n" | passwd root

}



general_setup () {

arch-chroot $mnt /bin/bash -e << EOF

echo -e 'en_US.UTF-8 UTF-8\nen_US ISO-8859-1' > /etc/locale.gen  

hwclock --systohc
ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime

echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'Arch-Linux' > /etc/hostname
echo 'KEYMAP=us' > /etc/vconsole.conf

cat > /etc/hosts <<EOF2
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF2

locale-gen

###  Install necessary applications with proper permissions
mkdir -p -m 750 /etc/sudoers.d

pacman --noconfirm -Sy sudo tar man

pacman --noconfirm -Sy dosfstools parted arch-install-scripts snapper git base-devel less

mkdir -p /etc/mkinitcpio.conf.d


if [ "$encrypt" -eq 1 ]; then

   echo 'HOOKS=(systemd autodetect keyboard sd-vconsole modconf block sd-encrypt resume filesystems)' > /etc/mkinitcpio.conf.d/myhooks.conf

   #echo 'HOOKS=(base udev autodetect modconf kms keyboard sd-vconsole block sd-encrypt filesystems resume fsck)' > /etc/mkinitcpio.conf.d/myhooks.conf

else

   echo 'HOOKS=(systemd autodetect modconf keyboard sd-vconsole block filesystems resume)' > /etc/mkinitcpio.conf.d/myhooks.conf

fi


mkinitcpio -p linux


# Autologin to tty1

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF2
[Service]
Type=simple
ExecStart=
ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin $user --noclear %I 38400 linux
EOF2


# Setup sudo
mkdir -p /etc/sudoers.d
echo "$user ALL=(ALL)  NOPASSWD: /usr/bin/btrfs-assistant-launcher" > /etc/sudoers.d/nopasswd
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel

# Default root password is: 123456
printf "123456\n123456\n" | passwd root

useradd -m $user -G wheel
printf "123456\n123456\n" | passwd $user

# Disable login by root
#passwd --lock root

echo '[[ $- != *i* ]] && return
alias ls="ls --color=auto"
alias grep="grep --color=auto"
alias vi="vim"
PS1="# "' > /root/.bashrc



###  Setup network  ###

pacman --noconfirm -Sy iw iwd dhcpcd

# Helps with slow booting caused by waiting for a connection
mkdir -p /etc/systemd/system/dhcpcd@.service.d/
cat > /etc/systemd/system/dhcpcd@.service.d/no-wait.conf << EOF2
[Service]
ExecStart=
ExecStart=/usr/bin/dhcpcd -b -q %I
EOF2

mkdir -p /etc/iwd
cat > /etc/iwd/main.conf << EOF2
[General]
EnableNetworkConfiguration=true
EOF2

# So iwd can automatically connect without any further interaction
mkdir -p /var/lib/iwd
cat > /var/lib/iwd/BELL364.psk << EOF2
[Security]
Passphrase=13FDC4A93E3C
EOF2

echo "Enabling network services..."
systemctl enable iwd.service dhcpcd.service

EOF


###  Finish setting up user  ###

sudo -u $user mkdir -p .local/bin

echo '# If running bash
if [ -n "$BASH_VERSION" ]; then

    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

PATH="$HOME/.local/bin:$PATH"

export EDITOR=/usr/bin/vi
export QT_QPA_PLATFORM=wayland
export QT_IM_MODULE=Maliit
export MOZ_ENABLE_WAYLAND=1
export XDG_RUNTIME_DIR=/run/$USER/1000
export RUNLEVEL=3
export QT_LOGGING_RULES="*=false"

if [[ ! "${DISPLAY}" && "${XDG_VTNR}" == 1 ]]; then
      echo "Auto-logged in."
fi' > $mnt/home/$user/.bash_profile
chown user:user $mnt/home/$user/.bash_profile

touch $mnt/home/$user/.hushlogin
chown user:user $mnt/home/$user/.hushlogin

echo '[[ $- != *i* ]] && return
alias ls="ls --color=auto"
alias grep="grep --color=auto"
alias vi="vim"
PS1="$ "' > $mnt/home/$user/.bashrc
chown user:user $mnt/home/$user/.bashrc

# Remember last cursor position in vim
cat > $mnt/home/$user/.vimrc << EOF
au BufReadPost *
     if line("'\"") > 0 && line("'\"") <= line("$") && &filetype != "gitcommit" | execute("normal \`\"") | endif
EOF
chown user:user $mnt/home/$user/.vimrc

}



setup_snapper () {


# Snapshot script
echo '#!/bin/bash

snapper --no-dbus create --read-write
snapper --no-dbus list

# Needs to be updated for grub-btrfs list
grub-mkconfig -o /boot/grub/grub.cfg' > $mnt/usr/local/bin/snapshot.sh
chmod +x $mnt/usr/local/bin/snapshot.sh


arch-chroot $mnt /bin/bash -e << EOF

snapper --no-dbus -c root create-config /
snapper --no-dbus list-configs

# Automate snapper and btrfs services  ###
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer
#systemctl enable snapper-boot.timer
 
#systemctl enable btrfs-balance.timer
systemctl enable btrfs-scrub@-.timer
#systemctl enable btrfs-trim.timer
 
# Have snapper take a snapshot every 20 mins (default is every 1hr)
mkdir -p /etc/systemd/system/snapper-timeline.timer.d/
cat > /etc/systemd/system/snapper-timeline.timer.d/frequency.conf << EOF2
[Timer]
OnCalendar=
OnCalendar=*:0/20
EOF2

echo "To edit snapper config, run: vi /etc/snapper/configs/root"

# Needs to be run on inital snapshot
/etc/grub.d/41_snapshots-btrfs

systemctl enable grub-btrfsd

snapshot.sh

EOF


}



install_aur () {

arch-chroot $mnt /bin/bash -e << EOF

cd /home/$user
rm -rf yay-bin

sudo -u $user git clone https://aur.archlinux.org/yay-bin

cd yay-bin
sudo -u user makepkg -si

sudo -u $user yay -Y --gendb

EOF

}



install_tweaks () {

pacstrap -K $mnt terminus-font rsync reflector

echo 'FONT=ter-132b' >> $mnt/etc/vconsole.conf
echo 'vm.swappiness = 10' > $mnt/etc/sysctl.d/99-swappiness.conf
echo 'BINARIES=(setfont)' > $mnt/etc/mkinitcpio.conf.d/setfont.conf
echo 'MODULES=(lz4 lz4hc lz4hc_compress)' > $mnt/etc/mkinitcpio.conf.d/lz4.conf

arch-chroot $mnt systemctl enable systemd-oomd

sed -Ei 's/^#(Color)$/\1\nILoveCandy/;s/^#(ParallelDownloads).*/\1 = 10/' $mnt/etc/pacman.conf


###  Make backups of boot when pacman is updated  ###

mkdir -p $mnt/etc/pacman.d/hooks
cat > $mnt/etc/pacman.d/hooks/50-bootbackup.hook <<EOF
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Path
Target = usr/lib/modules/*/vmlinuz

[Action]
Depends = rsync
Description = Backing up /boot...
When = PostTransaction
Exec = /usr/bin/rsync -a --delete /boot /.bootbackup
EOF

systemctl enable reflector.timer

#sudo -u $user yay mkinitcpio-overlayfs

arch-chroot $mnt mkinitcpio -p linux

}



reset_keys () {

rm -rf /etc/pacman.d/gnupg
pacman-key --init
pacman-key --populate

}


copy_script () {

echo -e "\nCopying script to $mnt\n"
cp arch.sh $mnt

}



do_chroot () {

check_on_root
copy_script
mount_mount

echo -e "\nEntering chroot. Type 'exit' to leave.\n"

arch-chroot $mnt /bin/bash -ic 'exec env PS1="(chroot) # " bash --norc'

echo -e "\nExiting chroot...\n"

}



chroot_install () {

   check_on_root
   copy_script

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

   pacman -S plasma-desktop plasma-wayland-session plasma-pa dolphin konsole firefox

   cd /home/$user
   sudo -u $user yay btrfs-assistant
   
}



download_script () {

echo -e "\nDowloading scripts from Github..."

curl -s https://raw.githubusercontent.com/bathtime/arch/main/arch.sh > arch.sh

if [[ "$?" -eq 0 ]]; then
   echo "Download successful!"
   chmod +x arch.sh
else
   echo "Download unsuccessful."
fi

}



download_apps () {

pacman -S arch-install-scripts gptfdisk terminus-font 

}



mnt=/mnt
efiPart=1
biosPart=0
swapPart=2
rootPart=3
subvols=(var_cache var_log var_tmp)
user=user
hostname=Arch
encrypt=0
password=1234567890


# Make font big and readable
#pacman -S terminus-font
setfont ter-132b

if [[ ! "$1" = "" ]]; then
   disk=$1
else
   choose_disk
fi

check_viable_disk

loadkeys en

# Update system clock
#timedatectl

#[[ "$(cat /sys/firmware/efi/fw_platform_size)" -eq 64 ]] && echo "This computer is running in uefi mode" || echo "This computer is not running in uefi mode."



while [[ "${1}" != "" ]]; do
        case "${1}" in
        -c|--copy)      copy_script     ; exit ;;
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
"Install boot manager"
"Setup fstab"
"General setup"
"Install aur"
"Install tweaks"
"Setup snapper"
"Copy script"
"Chroot install"
"Chroot"
"Mount $mnt"
"Unmount $mnt"
"Print partitions"
"Delete partitions"
"Connect wireless"
"Download script"
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
	"Install boot manager") echo -e "\nWhich boot manager would you like to install?\n"
		
				choiceBoot=(grub efiSTUB rEFInd quit) 

				select choiceBoot in "${choiceBoot[@]}"
				do
					case $choiceBoot in
						"grub")		install_GRUB ;;
						"efiSTUB")	install_EFISTUB ;;
						"rEFInd")	install_REFIND ;;
						"quit")		exit ;;
						'')		echo -e "\nInvalid option!\n" ;;
					esac						
				done ;;
        "Setup fstab")		setup_fstab ;;
	"General setup")	general_setup ;;
        "Install aur")		install_aur ;;
        "Install tweaks")	install_tweaks ;;
	"Setup snapper")	setup_snapper ;;
        "Chroot")		do_chroot ;;
        "Chroot install")	chroot_install ;;
        "Mount $mnt")		mount_mount  ;;
        "Unmount $mnt")		unmount_disk  ;;
        "Print partitions")	print_partitions ;;
        "Delete partitions")	delete_partitions ;;
        "Copy script")		copy_script ;;
        "Connect wireless")	connect_wireless ;;
        "Download script")	download_script ;;
        "Download apps")	download_apps    ;;
        "Post setup")		post_setup ;;
        "Reset pacman keys")    reset_keys ;;
	"Quit")			echo -e "\nQuitting!"; exit; ;;
        '')			echo -e "\nInvalid option!\n"; ;;
    esac
done
