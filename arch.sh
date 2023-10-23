#!/bin/bash


# Download and run with:
# bash <(curl -sL bit.ly/a-install)


###  Set error detection  ###
 
error() {

   local sourcefile=$1
   local lineno=$2
   local errornum=$3
   local command=$4

   echo -e "\e[0;41m\n\n$1: Error $3 on line $2: \n\n$4\n\e[0;29m\n\n"

}

trap 'error "${BASH_SOURCE}" "${LINENO}" "$?" "${BASH_COMMAND}"' ERR

error_check () {

	if [ $1 -eq 1 ]; then
   	set -Eeo pipefail
	else
   	set +e 
	fi

}

# Used to temporarily disable at certain points in script (eg., as in the mount_disk function)
error_check 1

mnt=/mnt
espPart=1
swapPart=2
rootPart=3
rootfs=btrfs
subvols=()
efi_path=/efi

user=user
password=123456
aur_app=paru
aur_path=/home/$user

ucode=intel-ucode
hostname=Arch
reinstall=0

wifi_ssid="BELL364"
wifi_pass="13FDC4A93E3C"


# Post setup

post_install_apps="plasma-desktop plasma-wayland-session plasma-pa kscreen dolphin konsole firefox"
autostartapp="startplasma-wayland"



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

   	# Might need to turn error checking off here
   	error_check 1 

   	echo "Unmounting $mnt..."

   	# Shouldn't be in directory we're unmounting   
   	[[ "$(pwd | grep $mnt)" ]] && cd ..

   	sync
   	umount -n -R $mnt

   	if [[ "$(mount | grep 'on '$mnt)" ]]; then

      	echo -e "\nCouldn't unmount. Trying alternative method. Please be patient...\n" 

      	#findmnt -R $mnt

      	sync
      	umount -R -f $mnt
      	sleep 1

      	if [[ "$(mount | grep 'on '$mnt)" ]]; then
         	echo -e "\nCouldn't unmount. Using lazy method...\n" 
         	sleep 1
         	umount -R -l $mnt
      	fi
   	fi 

   	if [[ "$?" -eq 0 ]]; then
      	echo -e "\nUnmount successful.\n"
   	else
      	echo -e "\nERROR ($?): could not unmount!\n"
      	exit
   	fi 

	else
   	echo -e "\nDisk already unmounted!\n"
	fi

	error_check 1

}



choose_disk () {

	search_disks=1

	while [ $search_disks -eq 1 ]; do

		echo -e "\nDrives found:\n"

		lsblk --output=PATH,SIZE,MODEL,TRAN -d | grep -P "/dev/sd|nvme|vd"
		disks=$(lsblk -dpnoNAME|grep -P "/dev/sd|nvme|vd") 
		disks+=$(echo -e "\nrefresh\nquit")

		echo -e "\nWhich drive?\n"

		select disk in $disks
		do
   		case $disk in
				refresh) break;	;;
        		quit) 	echo -e "\nQuitting!"; exit; ;;
        		'')   	echo -e "\nInvalid option!\n" ; break ;;
        		*)    	search_disks=0; break; ;;
    		esac
		done

	done

	echo -e "\nSetup config:\n\ndisk: $disk\nuser: $user\n"

}



delete_partitions () {

	check_on_root
	unmount_disk

	echo -e "\nWiping disk...\n"

	wipefs -af $disk 

	[ ! "$(pacman -Qs $package)" ] && pacman -S gptfdisk

	sgdisk -Zo $disk

	# Not sure if this is required but can't hurt
	#echo "Wiping first 25mb of disk. Please be patient..."
	#dd if=/dev/zero of=$disk bs=1M count=25

}



create_partitions () {

	check_on_root
	delete_partitions

	parted -s $disk mklabel gpt
	parted -s --align=optimal $disk mkpart ESP fat32 1Mib 512Mib 
	parted -s $disk set $espPart esp on
	parted -s --align=optimal $disk mkpart SWAP linux-swap 512Mib 8512Mib
	parted -s $disk set $swapPart swap on
	parted -s --align=optimal $disk mkpart ROOT $rootfs 8512Mib 100%

	mkfs.fat -F 32 -n EFI $disk$espPart 
	mkswap -L SWAP $disk$swapPart

	if [ "$rootfs" = "btrfs" ]; then
		mkfs.btrfs -f -L ROOT $disk$rootPart
	else
		mkfs.ext4 -F -q -t ext4 -L ROOT $disk$rootPart
	fi

	parted -s $disk print


	echo -e "\nMounting $mnt..."
	mount --mkdir $disk$rootPart $mnt

	cd $mnt

	if [ "$rootfs" = "btrfs" ]; then

		for subvol in '' "${subvols[@]}"; do
   		btrfs su cr /mnt/@"$subvol"
		done

	fi

	mkdir -p $mnt/{etc,tmp}

	unmount_disk
	mount_disk

}



mount_disk () {

	check_on_root

	if [[ ! $(mount | grep -E "on /mnt") ]]; then


		if [ "$rootfs" = "btrfs" ]; then

			echo -e "\nMounting...\n"

			mountopts="noatime,compress-force=zstd:1,discard=async"

			for subvol in '' "${subvols[@]}"; do
   			mount --mkdir -o "$mountopts",subvol=@"$subvol" $disk$rootPart $mnt/"${subvol//_//}"
			done

		else

  			mount --mkdir $disk$rootPart $mnt

		fi

		# mount efi partition
		mount --mkdir $disk$espPart $mnt$efi_path

	fi

}



install_base () {

	check_on_root
	mount_disk
	copy_script


	#pacstrap_install base linux linux-firmware vim vi libarchive $ucode

	pacstrap_install base linux linux-firmware


   [ "$rootfs" = "btrfs" ] && pacstrap_install btrfs-progs || pacstrap_install e2fsprogs


	###  Prepare auto-login  ###

	# Does a user already exist?
	if [ ! "$(grep ^$user $mnt/etc/passwd)" ]; then
   	login_user=root
	else
   	login_user=$user
	fi

	echo -e "\nCreating auto-login for $login_user.\n"

	mkdir -p $mnt/etc/systemd/system/getty@tty1.service.d
	cat > $mnt/etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
Type=simple
ExecStart=
ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin $login_user --noclear %I 38400 linux
EOF

}



setup_fstab () {

	check_on_root
	mount_disk

	genfstab -U $mnt > $mnt/etc/fstab


	###  Tweak the resulting /etc/fstab generated  ###

	SWAP_UUID=$(blkid -s UUID -o value $disk$swapPart)

	# Changing compression
	sed -i 's/zstd:3/zstd:1/' $mnt/etc/fstab

	# Bad idea to use subids when rolling back 
	sed -i 's/subvolid=.*,//g' $mnt/etc/fstab

	# genfstab will generate a swap drive. we're using a swap file instead
	sed -i '/LABEL=SWAP/d; /none.*swap.*defaults/d' $mnt/etc/fstab

	# Make /efi read-only
	#sed -i 's/\/efi.*vfat.*rw/\/efi     vfat     ro/' $mnt/etc/fstab

	[ ! "$(cat $mnt/etc/fstab | grep 'none swap defaults 0 0')" ] && echo -e "UUID=$SWAP_UUID none swap defaults 0 0\n" >> $mnt/etc/fstab
	[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /var/cache')" ] && echo "tmpfs    /var/cache  tmpfs   rw,nodev,nosuid,mode=1755,size=2G   0 0" >> $mnt/etc/fstab
	[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /var/log')" ]   && echo "tmpfs    /var/log    tmpfs   rw,nodev,nosuid,mode=1775,size=2G   0 0" >> $mnt/etc/fstab
	[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /var/tmp')" ]   && echo "tmpfs    /var/tmp    tmpfs   rw,nodev,nosuid,mode=1777,size=2G   0 0" >> $mnt/etc/fstab

	systemctl daemon-reload

	cat $mnt/etc/fstab

}



install_REFIND () {

	check_on_root
	mount_disk


	pacstrap_install refind 


	arch-chroot $mnt refind-install --usedefault $disk$espPart --alldrivers

	SWAP_UUID=$(blkid -s UUID -o value $disk$swapPart)
	ROOT_UUID=$(blkid -s UUID -o value $disk$rootPart)

   if [ "$rootfs" = "btrfs" ]; then
		rootflags='subvol=@'
	else
		rootflags=/
	fi

	echo "\"Boot with standard options\"  \"root=UUID=$ROOT_UUID rw rootflags=$rootflags quiet nmi_watchdog=0 loglevel=3 rd.udev.log_level=3 resume=UUID=$SWAP_UUID zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=20 zswap.zpool=z3fold\"" > $mnt/boot/refind_linux.conf

	echo "\"Boot read only\"  \"root=UUID=$ROOT_UUID ro rootflags=$rootflags quiet nmi_watchdog=0 loglevel=3 rd.udev.log_level=3 resume=UUID=$SWAP_UUID zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=20 zswap.zpool=z3fold\"" >> $mnt/boot/refind_linux.conf

	sed -i 's/#textonly/textonly/g; s/timeout .*/timeout 3/g; s/#also_scan_dirs boot,@/also_scan_dirs +,boot,@/g' $mnt$efi_path/EFI/BOOT/refind.conf

	rm -rf /boot/grub

	echo -e "\nYou should have a fully bootable system now. Feel free to test it.\n"

}



install_GRUB () {

	check_on_root
	mount_disk


   pacstrap_install grub grub-btrfs os-prober efibootmgr inotify-tools lz4


	SWAP_UUID=$(blkid -s UUID -o value $disk$swapPart)

	arch-chroot $mnt /bin/bash -e << EOF

	grub-install --target=x86_64-efi --efi-directory=$efi_path --bootloader-id=GRUB --removable

	cat > /etc/default/grub << EOF2

GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=""
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="nowatchdog loglevel=3 rd.udev.log_level=3 resume=UUID=$SWAP_UUID zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=20 zswap.zpool=z3fold"
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



	###  Offer readonly grub booting option  ###

	cp $mnt/etc/grub.d/10_linux /etc/grub.d/10_linux-readonly
	sed -i 's/\"\$title\"/\"\$title \(readonly\)\"/g' $mnt/etc/grub.d/10_linux-readonly
	sed -i 's/ rw / ro /g' $mnt/etc/grub.d/10_linux-readonly

	# So systemd won't remount as 'rw'
	arch-chroot $mnt systemctl mask systemd-remount-fs.service

	grub-mkconfig -o /boot/grub/grub.cfg

EOF

	echo -e "\nYou should have a fully bootable system now. Feel free to test it.\n"

}


install_EFISTUB () {

	echo "TODO."

	exit

	mount_disk

	SWAP_UUID=$(blkid -s UUID -o value $disk$swapPart)
	ROOT_UUID=$(blkid -s UUID -o value $disk$rootPart)


	echo 'ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"
ALL_microcode=(/boot/*-ucode.img)

PRESETS=("default")

default_image="/efi/EFI/boot/initramfs-linux.img"
#default_image="/boot/initramfs-linux.img"
#default_image="/boot/efi/boot/bootx64.efi"
#default_uki="/efi/EFI/Linux/arch-linux.efi"' > $mnt/etc/mkinitcpio.d/linux.preset

	#[ ! -f $mnt/usr/bin/efibootmgr ] && pacstrap -K $mnt efibootmgr
   pacstrap_install efibootmgr

	arch-chroot $mnt /bin/bash -e << EOF

	mkinitcpio -p linux

	efibootmgr --create --disk $disk --part $espPart --label "Arch Linux" --loader "/vmlinuz-linux" --unicode "root=$ROOT_UUID rootflags=subvol=@ resume=$SWAP_UUID rw initrd=\EFI\boot\initramfs-linux.img"

	# An example of deleting entries:
	# efibootmgr -B 0001 -L 'Arch Linux 2'
	efibootmgr --unicode


EOF

}



install_uki () {

	echo "TODO."

	exit

	mount_disk

	SWAP_UUID=$(blkid -s UUID -o value $disk$swapPart)
	ROOT_UUID=$(blkid -s UUID -o value $disk$rootPart)

	echo "layout=uki" > $mnt/etc/kernel/install.conf

	echo "root=UUID=$ROOT_UUID rw resume=UUID=$SWAP_UUID" > $mnt/etc/kernel/cmdline

echo 'ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"
ALL_microcode=(/boot/*-ucode.img)

PRESETS=("default")

default_image="/efi/EFI/arch/initramfs-linux.img"
#default_image="/boot/initramfs-linux.img"
default_uki="/efi/EFI/Linux/arch-linux.efi"' > $mnt/etc/mkinitcpio.d/linux.preset

	mkdir -p $mnt/efi/EFI/{Linux,arch}

	arch-chroot $mnt /bin/bash -e << EOF
mkinitcpio -p linux

efibootmgr --create --disk $disk --part $espPart --label "Arch Linux" --loader '\EFI\Linux\arch-linux.efi' --unicode -o 0007,0004,0003

EOF

}



install_SYSTEMDBOOT () {

	echo "TODO"

	exit

	#arch-chroot $mnt bootctl --esp-path=/efi --boot-path=/boot install
	#arch-chroot $mnt bootctl --esp-path=/efi install
	arch-chroot $mnt bootctl install
	arch-chroot $mnt bootctl update
	arch-chroot $mnt systemctl enable systemd-boot-update.service 

}



general_setup () {

	check_on_root
	mount_disk
	copy_script


	echo -e 'en_US.UTF-8 UTF-8\nen_US ISO-8859-1' > $mnt/etc/locale.gen  
	echo 'LANG=en_US.UTF-8' > $mnt/etc/locale.conf
	echo 'Arch-Linux' > $mnt/etc/hostname
	echo 'KEYMAP=us' > $mnt/etc/vconsole.conf

	echo "127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname" > $mnt/etc/hosts

	echo '[[ $- != *i* ]] && return
alias ls="ls --color=auto"
alias grep="grep --color=auto"
alias vi="vim"
PS1="# "' > $mnt/root/.bashrc

	arch-chroot $mnt /bin/bash -e << EOF

	hwclock --systohc

	ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime

	locale-gen

	printf "$password\n$password\n" | passwd root

EOF

	cat > $mnt/root/.vimrc << EOF

au BufReadPost *
    \ if line("'\"") > 0 && line("'\"") <= line("$") && &filetype != "gitcommit" | 
    \ execute("normal \`\"") | 
    \ endif

set mouse=c

syntax on

set tabstop=3
set shiftwidth=3
set autoindent
set smartindent

EOF

}



setup_user () {

	check_on_root
	mount_disk
	copy_script


	pacstrap_install sudo


	mkdir -p -m 750 $mnt/etc/sudoers.d
	echo '%wheel ALL=(ALL:ALL) ALL' > $mnt/etc/sudoers.d/wheel

	if [ "$(grep -c "^$user" $mnt/etc/passwd)" -eq 0 ]; then
   	arch-chroot $mnt useradd -m user -G wheel
	else
		rm -rf $mnt/home/$user
   	arch-chroot $mnt userdel user
   	arch-chroot $mnt useradd -m user -G wheel
	fi

	if [ "$(grep -c "^$user" $mnt/etc/passwd)" -eq 0 ]; then
   	echo -e "\nUser was not created. Exiting.\n"
	   exit
	fi

	arch-chroot $mnt printf "$password\n$password\n" | passwd user

	# Autologin to tty1
	mkdir -p $mnt/etc/systemd/system/getty@tty1.service.d
	echo "[Service]
Type=simple
ExecStart=
ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin $user --noclear %I 38400 linux" > $mnt/etc/systemd/system/getty@tty1.service.d/autologin.conf

	[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /home/user/.cache')" ] && echo "tmpfs    /home/user/.cache    tmpfs   rw,nodev,nosuid,uid=$user,size=2G   0 0" >> $mnt/etc/fstab

	arch-chroot $mnt sudo -u $user mkdir -p /home/$user/.local/bin

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
export QT_LOGGING_RULES="*=false"' > $mnt/home/$user/.bash_profile
	chown user:user $mnt/home/$user/.bash_profile

	touch $mnt/home/$user/.hushlogin
	chown user:user $mnt/home/$user/.hushlogin

	echo '[[ $- != *i* ]] && return
alias ls="ls --color=auto"
alias grep="grep --color=auto"
alias vi="vim"
PS1="$ "' > $mnt/home/$user/.bashrc
	chown user:user $mnt/home/$user/.bashrc

	cp $mnt/root/.vimrc $mnt/home/$user/.vimrc
	chown user:user $mnt/home/$user/.vimrc

}



setup_network_iwd () {

	check_on_root
	mount_disk


	pacstrap_install iw iwd dhcpcd


	# Helps with slow booting caused by waiting for a connection
	mkdir -p $mnt/etc/systemd/system/dhcpcd@.service.d/
	echo '[Service]
ExecStart=
ExecStart=/usr/bin/dhcpcd -b -q %I' > $mnt/etc/systemd/system/dhcpcd@.service.d/no-wait.conf

   [ "$(cat $mnt/etc/dhcpcd.conf | grep noarp)" ] && echo noarp >> $mnt/etc/dhcpcd.conf

	mkdir -p $mnt/etc/iwd
	echo '[General]
EnableNetworkConfiguration=true

[Scan]
DisablePeriodicScan=true' > $mnt/etc/iwd/main.conf

	# So iwd can automatically connect without any further interaction
	mkdir -p $mnt/var/lib/iwd
	echo "[Security]
PreSharedKey=14ad650cdc57e587a5198d3be78cb4ef4dc2574a580949d3b9803774858c5abd
Passphrase=13FDC4A93E3C
SAE-PT-Group19=f5614183429496736ed0da01f20d14b3415e201531b6fc24987eb128c2090897dcb358dc0eac4716994f6dee52bd7cb642bc67f43106478fded1236655418a7a
SAE-PT-Group20=eb986ca0245dcd12c86bf779e36d4434973059133f10e12326cf319db32b98fed48e248f69e015bed36813f716581e13d56a21dbbda4fe3541e355afe49446458e8d8e47777b9866f720197effd6273b6e89cbdc140e58920cf269abe6ea0bf7" > $mnt/var/lib/iwd/"$wifi_ssid".psk

	echo "Enabling network services..."
	arch-chroot $mnt systemctl enable iwd.service dhcpcd.service

}



setup_network_wpa () {

	check_on_root
	mount_disk


	pacstrap_install iw wpa_supplicant dhcpcd


	arch-chroot $mnt systemctl enable wpa_supplicant.service

	mkdir -p $mnt/etc/wpa_supplicant
	arch-chroot $mnt wpa_passphrase "$wifi_ssid" "$wifi_pass" > $mnt/etc/wpa_supplicant/"$wifi_ssid".conf

}



setup_snapper () {

	check_on_root
	mount_disk

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

	check_on_root
	mount_disk


	pacstrap_install git less fakeroot pkg-config


	[ "$aur_app" = "paru" ] && pacstrap_install cargo


	arch-chroot $mnt /bin/bash << EOF

		cd $aur_path

		sudo -u $user git clone https://aur.archlinux.org/$aur_app.git

		cd $aur_app
		sudo -u $user makepkg -si

		sudo -u $user $aur_app --gendb

		chown -R $user:$user /home/$user/$aur_app

EOF


	#[ "$aur_app" = "paru" ] && arch-chroot $mnt pacman -R rust
	#[ "$aur_app" = "yay" ] && arch-chroot $mnt pacman -R rust

	#rm -rf $mnt/home/$user/{.cargo,$aur_app/*} $mnt/usr/lib/{go,rustlib}

}



install_tweaks () {

	check_on_root
	mount_disk


	pacstrap_install terminus-font ncdu dosfstools parted arch-install-scripts tar man gptfdisk


	echo 'FONT=ter-132b' >> $mnt/etc/vconsole.conf
	echo 'vm.swappiness = 10' > $mnt/etc/sysctl.d/99-swappiness.conf
	echo 'vm.vfs_cache_pressure=50' > $mnt/etc/sysctl.d/99-cache-pressure.conf
	sed -Ei 's/^#(Color)$/\1\nILoveCandy/;s/^#(ParallelDownloads).*/\1 = 10/' $mnt/etc/pacman.conf

	arch-chroot $mnt systemctl enable systemd-oomd

	echo 'kernel.core_pattern=/dev/null' > $mnt/etc/sysctl.d/50-coredump.conf

	mkdir -p $mnt/etc/systemd/coredump.conf.d/
	echo '[Coredump]
Storage=none
ProcessSizeMax=0' > $mnt/etc/systemd/coredump.conf.d/custom.conf

	echo '* hard core 0' > $mnt/etc/security/limits.conf

}



install_mksh () {

   ### TODO: Check that aur_app is installed!!!


	#arch-chroot $mnt sudo -u $user $aur_app -S mksh


exit

	#arch-chroot $mnt /bin/bash << EOF
	#sudo -u $user $aur_app --noconfirm -S mksh
#EOF

exit

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

	arch-chroot $mnt /bin/bash << EOF
chsh -s /usr/bin/mksh                          # root shell
echo 123456 | sudo -u $user chsh -s /bin/mksh  # user shell
EOF

}



install_liveroot () {

	check_on_root
	mount_disk


	pacstrap_install rsync squashfs-tools


	echo '#!/usr/bin/bash

create_archive() {
            
   echo -e "Creating archive file...\n"

   cd $real_root/@/

   mksquashfs . $real_root/@/root.squashfs -noappend -no-recovery -mem-percent 50 -e root.squashfs -e boot/* -e efi/* -e dev/* -e proc/* -e sys/* -e tmp/* -e run/* -e mnt/ -e .snapshots/ -e var/tmp/* -e var/cache/* -e var/log/* -e etc/pacman.d/gnupg/ -e var/lib/systemd/random-seed

   ls -la $real_root/@/root.squashfs

}

create_overlay() {

   echo -e "\nCreating overlay...\n"

   local lower_dir=$(mktemp -d -p /)
   local ram_dir=$(mktemp -d -p /)
   mount --move ${new_root} ${lower_dir}
   mount -t tmpfs cowspace ${ram_dir}
   mkdir -p ${ram_dir}/upper ${ram_dir}/work
   mount -t overlay -o lowerdir=${lower_dir},upperdir=${ram_dir}/upper,workdir=${ram_dir}/work rootfs ${new_root}

}


run_latehook() {


   echo -e "\nPress any key for extra boot options.\n"

   real_root=/real_root
   mkdir $real_root
   mount ${root} $real_root
   new_root=/new_root
   mkdir -p $new_root




   if read -t 2 -s -n 1; then

      echo -e "\nPlease choose an option:\n\n\
<s> run snapshot\n\
<w> run snapshot + overlay\n\
<o> run in overlay mode\n\
<e> run squashfs + overlay\n\
<n> create & run squashfs + overlay\n\
<c> copy / to tmpfs\n\
<d> emergency shell\n\n\
<enter> continue boot\n"

      read -n 1 -s key



      if [[ "$key" = "s" ]] || [[ "$key" = "w" ]]; then

         mount --mkdir -o subvolid=256 ${root} $new_root
      
         btrfs subvolume list -ts $new_root | less
	 read -n 3 -p "Enter snapshot number (or press <enter> for current subvolume (256)): " subvol 

	 if [ ! "$subvol" ]; then
            echo -e "\nDefault subvolum chosen.\n"
	    subvol=256
         fi

         echo -e "\nPlease enter extra mount options (ex., ro ):"
         read options 
         [ "$options" ] && options=","$options

         echo -e "\nWill proceed with the following mount:\n\nmount -o subvolid=$subvol$options ${root} /\n"

         umount $new_root
         mount --mkdir -o subvolid=$subvol$options ${root} $new_root

         if [ "$?" -ne 0 ]; then
            echo "Could not mount subvol ($subvol). Chosing default (256)."
            sleep 2
            mount --mkdir -o subvolid=256 ${root} $new_root 
         fi

         [[ "$key" = "w" ]] && create_overlay

      elif [[ "$key" = "o" ]]; then

         mount --mkdir -o subvolid=256 ${root} $new_root

         create_overlay

      elif [[ "$key" = "e" ]] || [[ "$key" = "n" ]] || [[ "$key" = "c" ]]; then

         if [[ "$key" = "e" ]] || [[ "$key" = "n" ]]; then

            [[ ! -f "$real_root/@/root.squashfs" ]] || [[ "$key" = "n" ]] && create_archive

            echo "Extracting archive to RAM. Please be patient..."

            #unsquashfs -d /new_root -f $real_root/@/root.squashfs
            
            mount "$real_root/@/root.squashfs" $new_root -t squashfs -o loop

            create_overlay

            umount -l $real_root

         elif [[ "$key" = "c" ]]; then

            mount -t tmpfs -o size=80% none $new_root

            echo "Copying root filesystem to RAM. Please be patient..."

            rsync -a --exclude=root.squashfs --exclude=/efi/ --exclude=/boot/ --exclude=/dev/ --exclude=/proc/ --exclude=/sys/ --exclude=/tmp/ --exclude=/run/ --exclude=/mnt/ --exclude=/.snapshots/* --exclude=/var/tmp/ --exclude=/var/cache/ --exclude=/var/log/ /real_root/@/ $new_root

         fi


      elif [[ "$key" = "d" ]]; then

         echo "Entering emergency shell."

         bash

      else

         echo "Continuing boot..."
         mount --mkdir -o subvolid=256 ${root} $new_root

      fi

   else

         echo -e "Running default option..."

         mount --mkdir -o subvolid=256 ${root} $new_root
          
   fi


}' > $mnt/usr/lib/initcpio/hooks/liveroot


	echo '#!/bin/sh

build() {
  add_binary rsync
  add_binary bash
  add_binary btrfs
  add_binary unsquashfs 
  add_binary mksquashfs
  #add_binary unionfs
  add_module overlay
  add_module loop
  add_module squashfs
  add_runscript
}

help() {
  cat << HELPEOF
Run Arch as tmpfs or overlay
HELPEOF
}' > $mnt/usr/lib/initcpio/install/liveroot


	echo 'MODULES=(lz4)
BINARIES=()
FILES=()
HOOKS=(base udev keyboard autodetect kms modconf sd-vconsole block filesystems liveroot resume)
COMPRESSION="lz4"
#COMPRESSION_OPTIONS=()
MODULES_DECOMPRESS="yes"' > $mnt/etc/mkinitcpio.conf

	echo 'ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"
ALL_microcode=(/boot/*-ucode.img)

PRESETS=("default")

#default_config="/etc/mkinitcpio.conf"
default_image="/boot/initramfs-linux.img"' > $mnt/etc/mkinitcpio.d/linux.preset

	arch-chroot $mnt mkinitcpio -P 

	# So systemd won't remount as 'rw'
	arch-chroot $mnt systemctl mask systemd-remount-fs.service

}



setup_snapshots () {

	check_on_root
	mount_disk

	rm -rf $mnt/.snapshots/
	mkdir -p $mnt/.snapshots

	rm -rf $mnt/snapshot
	touch $mnt/snapshot
	arch-chroot $mnt btrfs subvolume snapshot / /.snapshots/first
	rm $mnt/snapshot

}



reset_keys () {

	rm -rf /etc/pacman.d/gnupg
	pacman-key --init
	pacman-key --populate

}



do_chroot () {

	check_on_root
	mount_disk

	mount -t proc /proc $mnt/proc/
	mount -t sysfs /sys $mnt/sys/
	mount -o bind /dev $mnt/dev/
	mount -o bind /run $mnt/run/
	mount -o bind /sys/firmware/efi/efivars $mnt/sys/firmware/efi/efivars/

	cp /etc/resolv.conf $mnt/etc/resolv.conf

	echo -e "\e[0;42m\n \nEntering chroot. Type 'exit' to leave.\n\e[0;29m\n"

   chroot $mnt /bin/bash -ic 'exec env PS1="(chroot) # " bash --norc'

	echo -e "\e[0;42m\n \nExiting chroot.\n\e[0;29m\n"

   unmount_disk

}



connect_wireless () {

	echo -e "\nAttempting to connect to wireless...\n"

	iwctl station wlan0 scan

	iwctl --passphrase $wifi_pass station wlan0 connect $wifi_ssid

	if [[ "$?" -eq 0 ]]; then
   	echo "Connection successful!"
	else
   	echo "Connection unsuccessful."
	fi

}



post_setup () {


	pacstrap_install "$post_install_apps"


	echo 'if [[ ! "${DISPLAY}" && "${XDG_VTNR}" == 1 ]]; then
  	#autostartapp
fi' >> /home/$user/.bash_profile

	echo 'if [[ ! "${DISPLAY}" && "${XDG_VTNR}" == 1 ]]; then
   #autostartapp
fi' >> /home/$user/.profile
	chown user:user /home/$user/{.profile,bash_profile}

	sed -i "s/#autostartapp/$autostartapp/" $mnt/home/$user/{.profile,bash_profile}

}



backup_config () {

	cd /home/$user

	print_config

	sudo -u $user tar cvf setup.tar $CONFIG_FILES

	ls -la setup.tar
	#gpg -c setup.tar

	exit

}



restore_config () {

	cd /home/$user

	sudo -u $user tar xvf setup.tar

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



clone_disk () {

	check_on_root


	pacstrap_install rsync


	echo -e "\nCloning disk. Please be patient...\n"

	rsync -a --exclude=/dev/ --exclude=/proc/ --exclude=/sys/ --exclude=/tmp/ --exclude=/run/ --exclude=/mnt/ --exclude=/.snapshots/* --exclude=/var/tmp/ --exclude=/var/cache/ --exclude=/var/log/ --exclude=/mnt/ / $mnt/

	mkdir $mnt/{dev,proc,run,sys}

	echo -e"\n*** Remember to update fstab and install a boot manager! ***\n"

}


create_archive () {


	pacstrap_install squashfs-tools


	echo "Creating archive file..."

	cd / 
	rm -rf /root.squashfs

	time mksquashfs / root.squashfs -mem-percent 50 -no-recovery -noappend -e rootfs.tar.gz -e /boot/ -e /efi/ -e root.squashfs -e /dev/ -e /proc/ -e /sys -e /tmp -e /run -e /mnt -e /.snapshots/ -e /var/tmp/ -e /var/cache/ -e /var/log/ -e /etc/pacman.d/gnupg/

	ls -la root.squashfs

}



copy_script () {

	[ -d $mnt/home/$user ] && cp arch.sh $mnt/home/$user || cp arch.sh $mnt/
	
	[ $? -eq 0 ] && echo -e "\nScripts copied.\n" || echo -e "\nScripts could not be copied!!!\n"

}



pacstrap_install () {

   packages="$@"

	for package in $packages; do

		if [ "$reinstall" -eq 1 ]; then
			pacstrap -K $mnt $package
		else
	   	pacman --root $mnt -Qi $package &> /dev/null && echo "$package already installed." || pacstrap -K $mnt $package
		fi

	done

}


CONFIG_FILES=".config/baloofilerc
.config/dolphinrc
/.config/epy/configuration.json
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
mount-readonly.sh"



if [ "$1" ]; then
	disk="$1"
else
	choose_disk
fi

check_viable_disk



###  Install required packages  ###

packages=("arch-install-scripts
gptfdisk
squashfs-tools
less
terminus-font")

for package in $packages; do
	pacman -Qi $package &>/dev/null || pacstrap -K $mnt $package
done


loadkeys en

# Make font big and readable
setfont ter-132b


choices=("Quit"
"Chroot"
"Choose disk"
"Partition disk"
"Install base"
"Setup fstab"
"Install boot manager"
"General setup"
"Setup user"
"Setup network"
"Install aur"
"Install tweaks"
"Install mksh"
"Install liveroot"
"Setup snapshots"
"Setup snapper"
"Mount $mnt"
"Unmount $mnt"
"Create squashfs image"
"Clone disk"
"Configuration"
"Delete partitions"
"Clean system"
"Connect wireless"
"Download script"
"Post setup"
"Reset pacman keys"
"Change mount to /"
"Change mount to /mnt")


echo -e "\nPlease choose:\n"

select choice in "${choices[@]}" 
do
	case $choice in
		"Quit")						break; ;;
		"Chroot")					do_chroot ;;
      "Choose disk")				choose_disk ;;
      "Partition disk")			create_partitions ;;
      "Install base")			install_base ;;
      "Setup fstab")				setup_fstab ;;
		"Install boot manager") echo -e "\nWhich boot manager would you like to install?\n"

										choiceBoot=(rEFInd grub EFISTUB uki systemD quit) 
				
										select choiceBoot in "${choiceBoot[@]}"
										do
											case $choiceBoot in
												"rEFInd")	install_REFIND; break ;;
												"grub")		install_GRUB; break ;;
												"EFISTUB")	install_EFISTUB; break ;;
												"uki")	   install_uki; break ;;
												"systemD")	install_SYSTEMDBOOT; break ;;
												"quit")		break ;;
												'')			echo -e "\nInvalid option!\n" ;;
											esac						
										done ;;

		"General setup")			general_setup ;;
		"Setup user")				setup_user ;;
      "Setup network") 			echo -e "\nWhich network manager would you like to install?\n"
		
										choices=(iwd wpa_supplicant quit) 

										select choice in "${choices[@]}"
										do
											case $choice in
												"iwd")				setup_network_iwd; break ;;
												"wpa_supplicant")	setup_network_wpa; break ;;
												"quit")				break ;;
												'')					echo -e "\nInvalid option!\n" ;;
											esac						
										done ;;

		"Install aur")				install_aur ;;
      "Install tweaks")			install_tweaks ;;
      "Install mksh")			install_mksh ;;
		"Install liveroot")		install_liveroot ;;
		"Setup snapshots")		setup_snapshots ;;
		"Setup snapper")			setup_snapper ;;
      "Mount $mnt")				mount_disk  ;;
      "Unmount $mnt")			unmount_disk  ;;
		"Clone disk")				clone_disk ;;
		"Create squashfs image")	create_archive ;;
		"Configuration")			echo -e "\nPlease choose an option:\n"
		
										choiceConfig=(backup restore print delete quit) 

										select choiceConfig in "${choiceConfig[@]}"
										do
											case $choiceConfig in
												"backup")	backup_config ;;
												"restore")	restore_config ;;
												"quit")		break ;;
												'')			echo -e "\nInvalid option!\n" ;;
											esac						
										done ;;

		"Delete partitions")		delete_partitions ;;
		"Clean system")			clean_system ;;
      "Connect wireless")		connect_wireless ;;
      "Download script")		download_script ;;
      "Post setup")				post_setup ;;
      "Reset pacman keys")    reset_keys ;;
		"Change mount to /")		mnt='' ;;
		"Change mount to /mnt")	mnt=/mnt ;;
      '')							echo -e "\nInvalid option!\n"; ;;
	esac
done


unmount_disk


