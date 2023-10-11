#!/bin/bash


# Run with:
# bash <(curl -sL bit.ly/a-install)

#set -e

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
parted -s $disk set $espPart esp on
parted -s --align=optimal $disk mkpart SWAP linux-swap 1005Mib 10Gib
parted -s $disk set $swapPart swap on
parted -s --align=optimal $disk mkpart ROOT btrfs 10Gib 100%

mkfs.fat -F 32 -n EFI $disk$espPart 
mkswap $disk$swapPart
mkfs.btrfs -f -L ROOT $disk$rootPart

parted -s $disk print


echo -e "\nMounting $mnt..."
mount --mkdir $disk$rootPart $mnt

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

mountopts="noatime,compress-force=zstd:1,discard=async"

echo -e "\nMounting...\n"
for subvol in '' "${subvols[@]}"; do
    mount --mkdir -o "$mountopts",subvol=@"$subvol" $disk$rootPart $mnt/"${subvol//_//}"
    echo "mount -o $mountopts,subvol=@$subvol $disk$rootPart /mnt/${subvol//_//}"
done

mkdir -p $mnt/{etc,tmp}

# mount efi partition
mount --mkdir $disk$espPart $mnt/efi

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

extra_cmd=

arch-chroot $mnt /bin/bash -e << EOF

grub-install --target=x86_64-efi --efi-directory=/efi/ --bootloader-id=GRUB --removable

cat > /etc/default/grub << EOF2

GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=""
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="nowatchdog loglevel=3 rd.udev.log_level=3 resume=UUID=$SWAP_UUID zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=20 zswap.zpool=z3fold $extra_cmd"
GRUB_DISABLE_RECOVERY="true"
GRUB_HIDDEN_TIMEOUT=2
GRUB_RECORDFAIL_TIMEOUT=1
GRUB_TIMEOUT=0
 
# Update grub with:
# grub-mkconfig -o /boot/grub/grub.cfg

EOF2


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

# Bad idea to use subids when rolling back 
sed -i 's/subvolid=.*,//g' $mnt/etc/fstab

# genfstab will generate a swap drive. we're using a swap file instead
sed -i '/LABEL=SWAP/d; /none.*swap.*defaults/d' $mnt/etc/fstab

# Make /efi read-only
sed -i 's/\/efi.*vfat.*rw/\/efi     vfat     ro/' $mnt/etc/fstab


[ ! "$(cat $mnt/etc/fstab | grep 'none swap defaults 0 0')" ] && echo "UUID=$SWAP_UUID none swap defaults 0 0" >> $mnt/etc/fstab

# Put ~/.cache in tmpfs
[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /home/user/.cache')" ] && echo "tmpfs    /home/user/.cache    tmpfs   rw,nodev,nosuid,uid=$user,size=2G   0 0" >> $mnt/etc/fstab

[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /var/cache')" ] && echo "tmpfs    /var/cache  tmpfs   rw,nodev,nosuid,mode=1755,size=2G   0 0" >> $mnt/etc/fstab
[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /var/log')" ]   && echo "tmpfs    /var/log    tmpfs   rw,nodev,nosuid,mode=1775,size=2G   0 0" >> $mnt/etc/fstab
[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /var/run')" ]   && echo "tmpfs    /var/run    tmpfs   rw,nodev,nosuid,mode=1777,size=2G   0 0" >> $mnt/etc/fstab


systemctl daemon-reload

cat $mnt/etc/fstab

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

pacman --noconfirm -Sy dosfstools parted arch-install-scripts snapper git base-devel

mkdir -p /etc/mkinitcpio.conf.d


#echo 'HOOKS=(base udev autodetect modconf kms keyboard sd-vconsole block filesystems resume fsck)' > /etc/mkinitcpio.conf.d/myhooks.conf
echo 'HOOKS=(systemd autodetect modconf keyboard sd-vconsole block filesystems resume)' > /etc/mkinitcpio.conf.d/myhooks.conf

echo 'MODULES_DECOMPRESS="yes"' > /etc/mkinitcpio.conf.d/decomp.conf
echo 'COMPRESSION="lz4"'        > /etc/mkinitcpio.conf.d/compress.conf
echo 'MODULES="lz4"'            > /etc/mkinitcpio.conf.d/modules.conf

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

printf "$password\n$password\n" | passwd root

useradd -m $user -G wheel
printf "$password\n$password\n" | passwd $user

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

export EDITOR=/usr/bin/vim
export QT_QPA_PLATFORM=wayland
export QT_IM_MODULE=Maliit
export MOZ_ENABLE_WAYLAND=1
export XDG_RUNTIME_DIR=/run/$USER/1000
export RUNLEVEL=3
export QT_LOGGING_RULES="*=false"
' > $mnt/home/$user/.bash_profile
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
    \ if line("'\"") > 0 && line("'\"") <= line("$") && &filetype != "gitcommit" | 
    \ execute("normal \`\"") | 
    \ endif

syntax on
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
#systemctl enable btrfs-scrub@-.timer
#systemctl enable btrfs-trim.timer
 
# Have snapper take a snapshot every 120 mins (default is every 1hr)
mkdir -p /etc/systemd/system/snapper-timeline.timer.d/
cat > /etc/systemd/system/snapper-timeline.timer.d/frequency.conf << EOF2
[Timer]
OnCalendar=
OnCalendar=*:0/120
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

sudo -u $user git clone https://aur.archlinux.org/paru.git
cd paru
sudo -u $user makepkg -si

sudo -u $user paru --gendb

pacman -R --noconfirm rust

EOF

}



install_tweaks () {


pacstrap -K $mnt terminus-font mksh

echo 'FONT=ter-132b' >> $mnt/etc/vconsole.conf
echo 'vm.swappiness = 10' > $mnt/etc/sysctl.d/99-swappiness.conf

arch-chroot $mnt systemctl enable systemd-oomd

sed -Ei 's/^#(Color)$/\1\nILoveCandy/;s/^#(ParallelDownloads).*/\1 = 10/' $mnt/etc/pacman.conf



###  Shell (change to mksh)  ###

echo 'HISTFILE=/root/.mksh_history
HISTSIZE=5000
export VISUAL="emacs"
export EDITOR="/usr/bin/vim"
set -o emacs' > $mnt/root/.mkshrc

echo 'HISTFILE=/home/$USER/.mksh_history
HISTSIZE=5000
export VISUAL="emacs"
export EDITOR="/usr/bin/vim"
set -o emacs' > $mnt/home/$user/.mkshrc
chown user:user $mnt/home/$user/.mkshrc

echo -e 'PATH="$HOME/.local/bin:$PATH"
 
export EDITOR=/usr/bin/vim
export ENV="/home/$USER/.mkshrc"
export QT_QPA_PLATFORM=wayland
export QT_IM_MODULE=Maliit
export MOZ_ENABLE_WAYLAND=1
export XDG_RUNTIME_DIR=/tmp/runtime-user
export XDG_RUNTIME_DIR=/run/$USER/1000
export RUNLEVEL=3
export QT_LOGGING_RULES="*=false"

' > $mnt/home/$user/.profile
chown user:user $mnt/home/$user/.profile 

arch-chroot $mnt chsh -s /bin/mksh                                # root shell
arch-chroot $mnt echo 123456 | sudo -u user chsh -s /bin/mksh     # user shell



###  Offer readonly grub booting option  ###

cp $mnt/etc/grub.d/10_linux /etc/grub.d/10_linux-readonly
sed -i 's/\"\$title\"/\"\$title \(readonly\)\"/g' $mnt/etc/grub.d/10_linux-readonly
sed -i 's/ rw / ro /g' $mnt/etc/grub.d/10_linux-readonly

echo '#!/bin/bash

if [[ $(mount | grep " on / " | grep "ro") ]] || [[ "$1" = "-a" ]]; then

   tmp_dir=/home/user/.cache
   #mount -o uid=user -t tmpfs tmpfs $tmp_dir

   cd /home/user
   sudo -u user cp -r -p .{local,config,mozilla} $tmp_dir/

   mount -o uid=user -t tmpfs tmpfs /home/user/.config
   mount -o uid=user -t tmpfs tmpfs /home/user/.local
   mount -o uid=user -t tmpfs tmpfs /home/user/.mozilla

   sudo -u user cp -r $tmp_dir/.{config,local,mozilla} /home/user/

fi' > $mnt/usr/local/bin/mount-user-tmpfs.sh
chmod +x $mnt/usr/local/bin/mount-user-tmpfs.sh

# So systemd won't remount as 'rw'
arch-chroot $mnt systemctl mask systemd-remount-fs.service

echo '[Unit]
Description=Run script with systemd right before login prompt
After=rc-local.service
Before=getty.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/mount-user-tmpfs.sh

[Install]
WantedBy=multi-user.target' > $mnt/etc/systemd/system/readonly.service 

arch-chroot $mnt systemctl enable readonly.service



###  Add overlay boot option in grub menu  ###

arch-chroot $mnt sudo -u $user paru mkinitcpio-overlay
sudo sed -i 's/fallback initramfs/overlay initramfs/g' $mnt/etc/grub.d/{10_linux,10_linux-readonly}

echo 'ALL_config="/etc/mkinitcpio-overlay.conf"
ALL_kver="/boot/vmlinuz-linux"
ALL_microcode=(/boot/*-ucode.img)

PRESETS=("fallback")

fallback_image="/boot/initramfs-linux-fallback.img"
fallback_options="-S autodetect" > $mnt/etc/mkinitcpio.d/linux-overlay.preset

echo 'MODULES=(lz4)
BINARIES=()
FILES=()
HOOKS=(base udev autodetect modconf keyboard sd-vconsole block filesystems overlayfs resume)
COMPRESSION="lz4"
MODULES_DECOMPRESS="yes"' > $mnt/etc/mkinitcpio-overlay.conf 

arch-chroot $mnt mkinitcpio -p linux-overlay

arch-chroot $mnt grub-mkconfig -o /boot/grub/grub.cfg

}



clean_system () {

arch-chroot $mnt /bin/bash -e << EOF

  rm -rf /var/log/*
  pacman -S ncdu
  pacman -Scc
  sudo pacman -Qtdq
  
EOF

# Clean pacman cache after every transaction
mkdir -p $mnt/etc/pacman.d/hooks
echo '[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *
[Action]
Description = Cleaning pacman cache...
When = PostTransaction
Exec = /usr/bin/pacman -Scc' > $mnt/etc/pacman.d/hooks/clean_package_cache.hook


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

pacman -S plasma-desktop plasma-wayland-session plasma-pa kscreen dolphin konsole firefox

echo '
if [[ ! "${DISPLAY}" && "${XDG_VTNR}" == 1 ]]; then
   startplasma-wayland
fi
' >> /home/$user/.bash_profile

chown user:user /home/$user/.bash_profile

echo '
if [[ ! "${DISPLAY}" && "${XDG_VTNR}" == 1 ]]; then
   startplasma-wayland
fi
' >> /home/$user/.profile

chown user:user /home/$user/.profile

cd /home/$user
sudo -u $user paru btrfs-assistant
   
}



backup_config () {

cd /home/$user

print_config

sudo -u $user tar cvf setup.tar $CONFIG_FILES

ls -la setup.tar
#gpg -c setup.tar

exit

}



print_config () {

cd /home/$user

for FILE in $CONFIG_FILES
do
    ls -la "$FILE"
done

find . -type f -printf "%-.22T+ %.8TX %p\n" | sort | cut -f 2- -d ' '

}



restore_config () {

cd /home/$user

sudo -u $user tar xvf setup.tar

}



delete_config () {

cd /home/user

for FILE in $CONFIG_FILES
do
    ls -la "$FILE"
    rm -rf "$FILE"
done

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
espPart=1
swapPart=2
rootPart=3
subvols=()

user=user
hostname=Arch
password=123456



CONFIG_FILES="
.config/baloofilerc
.config/dolphinrc
.config/epy/configuration.json
.config/fontconfig/fonts.conf
.config/gtkrc
.config/gtkrc-2.0
.config/kactivitymanagerd-pluginsrc
.config/kactivitymanagerdrc
.config/kcminputrc
.config/kded5rc
.config/kdedefaults/package
.config/kdeglobals
.config/kfontinstuirc
.config/kglobalshortcutsrc
.config/konsolerc
.config/konsolesshconfig
.config/krunnerrc
.config/kscreenlockerrc
.config/ksplashrc
.config/ksmserverrc
.config/kwinrc
.config/kwinrulesrc
.config/plasma-org.kde.plasma.desktop-appletsrc
.config/plasmashellrc
.config/powermanagementprofilesrc
.config/systemsettingsrc
.config/Trolltech.conf
.local/bin/*
.local/share/color-schemes/*
.local/share/dolphin/dolphinstaterc
.local/share/konsole/*.profile
.local/share/kxmlgui5/konsole/konsoleui.rc
.local/share/kxmlgui5/konsole/sessionui.rc
.local/share/plasma/plasmoids/*
.local/share/user-places.xbel
.mozilla/*
.viminfo
.vimrc
mount-readonly.sh
"


# Make font big and readable
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
"Overlay support"
"Copy script"
"Chroot install"
"Chroot"
"Mount $mnt"
"Unmount $mnt"
"Configuration"
"Print partitions"
"Delete partitions"
"Clean system"
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
        "Overlay support")	overlay_support ;;
        "Chroot")		do_chroot ;;
        "Chroot install")	chroot_install ;;
        "Mount $mnt")		mount_mount  ;;
        "Unmount $mnt")		unmount_disk  ;;
	"Configuration") echo -e "\nPlease choose an option:\n"
		
				choiceConfig=(backup restore print delete quit) 

				select choiceConfig in "${choiceConfig[@]}"
				do
					case $choiceConfig in
						"backup")	backup_config ;;
						"restore")	restore_config ;;
						"print")	print_config ;;
						"delete")	delete_config ;;
						"quit")		exit ;;
						'')		echo -e "\nInvalid option!\n" ;;
					esac						
				done ;;
        "Print partitions")	print_partitions ;;
        "Delete partitions")	delete_partitions ;;
	"Clean system")		clean_system ;;
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

