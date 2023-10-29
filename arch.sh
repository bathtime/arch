#!/bin/bash


# Documentation

: << DOCS

To run on the fly:
bash <(curl -sL bit.ly/a-install)




DOCS



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
espPartNum=1
swapPartNum=2
rootPartNum=3
espPart=$espPartNum
swapPart=$swapPartNum
rootPart=$rootPartNum
rootfs=btrfs
subvols=()
efi_path=/efi
encryption=0

user=user
password=123456
aur_app=paru
aur_path=/home/$user

ucode=intel-ucode
hostname=Arch
offline=0
reinstall=0
root_only=0
initramfs=mkinitcpio

wifi_ssid="BELL364"
wifi_pass="13FDC4A93E3C"


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

	echo "Syncing..."

	sync

	error_check 0 

	if [[ "$(mountpoint $mnt | grep 'is a')" ]]; then

		# Might need to turn error checking off here

		echo "Unmounting $mnt..."

		# Shouldn't be in directory we're unmounting   
		[[ "$(pwd | grep $mnt)" ]] && cd ..

		umount -n -R $mnt

		# Time to get rugged and tough!
		if [[ "$(mountpoint $mnt | grep 'is a')" ]]; then

			echo -e "\nCouldn't unmount. Trying alternative method. Please be patient...\n" 

			mounted=1

			while [[ "$mounted" -eq 1 ]]; do
				
				cd /

				if [[ "$(mountpoint $mnt | grep 'is a')" ]]; then
					sleep 2
					umount -l $mnt
				else
					mounted=0
				fi

			done

			systemctl daemon-reload

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
		disks+=$(echo -e "\nhost\nrefresh\nquit")

		echo -e "\nWhich drive?\n"

		select disk in $disks
		do
			case $disk in
				host)		disk="$(mount | awk '/ on \/ / { print $1}' | sed 's/[0-9]$//g')"; search_disks=0 ; break ;;
				refresh) break;	;;
				quit) 	echo -e "\nQuitting!"; exit; ;;
				'')   	echo -e "\nInvalid option!\n" ; break ;;
				*)    	search_disks=0; break; ;;
			esac
		done

	done

	echo -e "\nSetup config:\n\ndisk: $disk\nuser: $user\n"

        if [ "$(echo $disk | grep nvme)" ]; then
                espPart="p$espPartNum"
                swapPart="p$swapPartNum"
                rootPart="p$rootPartNum"
        fi
}



delete_partitions () {

	check_on_root
	unmount_disk

	echo -e "\nWiping disk...\n"

	wipefs -af $disk 

	[ ! "$(pacman -Qs $package)" ] && pacman -S gptfdisk

	sgdisk -Zo $disk

}



create_partitions () {

	check_on_root
	delete_partitions
	
	systemctl daemon-reload

	parted -s $disk mklabel gpt \
			mkpart ESP fat32 1Mib 512Mib \
			set $espPartNum esp on \
			mkpart SWAP linux-swap 512Mib 8512Mib \
			set $swapPartNum swap on \
			mkpart ROOT $rootfs 8512Mib 100% \

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

	mkdir -p $mnt/{etc,tmp,root,var/cache/pacman/pkg}
	chmod 750 $mnt/root
 
}



install_base () {

	check_on_root
	mount_disk

echo '[options]
HoldPkg     = pacman glibc
Architecture = auto

CheckSpace
ParallelDownloads = 10

[custom]
SigLevel = Optional TrustAll
Server = file:///var/cache/pacman/pkg/
' > /etc/pacman-offline.conf
	cp /etc/pacman-offline.conf $mnt/etc/pacman-offline.conf
	
	reset_keys
	packages="base linux linux-firmware vim parted gptfdisk arch-install-scripts pacman-contrib tar"
	#pacstrap_install base linux linux-firmware vim parted gptfdisk arch-install-scripts pacman-contrib tar

	[ "$root_only" ] && packages="$packages sudo"

	[ "$rootfs" = "btrfs" ] && packages="$packages btrfs-progs"

	pacstrap_install "$packages"


	###  Prepare auto-login  ###

	# Does a user already exist?
	if [ ! "$(grep ^$user $mnt/etc/passwd)" ] || [ "$root_only" -eq 1 ]; then
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



hypervisor_setup () {

	echo -e "\nNot tested. Run at your own risk!\n"
	exit

    hypervisor=$(systemd-detect-virt)

    case $hypervisor in

        kvm )       pacstrap_install qemu-guest-agent
              	     systemctl enable qemu-guest-agent --root=$mnt
                    ;;
        vmware  )   pacstrap_install open-vm-tools
                    systemctl enable vmtoolsd --root=$mnt
                    systemctl enable vmware-vmblock-fuse --root=$mnt
                    ;;
        oracle )    pacstrap_install virtualbox-guest-utils
                    systemctl enable vboxservice --root=$mnt
                    ;;
        microsoft ) pacstrap_install hyperv
                    systemctl enable hv_fcopy_daemon --root=$mnt
                    systemctl enable hv_kvp_daemon --root=$mnt
                    systemctl enable hv_vss_daemon --root=$mnt
                    ;;
	esac

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
#	[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /var/cache')" ] && echo "tmpfs    /var/cache  tmpfs   rw,nodev,nosuid,mode=1755,size=2G   0 0" >> $mnt/etc/fstab
	[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /var/log')" ]   && echo "tmpfs    /var/log    tmpfs   rw,nodev,nosuid,mode=1775,size=2G   0 0" >> $mnt/etc/fstab
	[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /var/tmp')" ]   && echo "tmpfs    /var/tmp    tmpfs   rw,nodev,nosuid,mode=1777,size=2G   0 0" >> $mnt/etc/fstab

	systemctl daemon-reload

	cat $mnt/etc/fstab

}



choose_initramfs () {

   echo -e "\nWhich initramfs would you like to install?\n"

	if [ "$1" ]; then
		choiceInitramfs=$1
	else
		choiceInitramfs=(mkinitcpio dracut booster quit)
	fi

   select choice in "${choiceInitramfs[@]}"
   do
      case $choice in
         "mkinitcpio")  	pacstrap_install mkinitcpio; break ;;
         "dracut")      	pacstrap_install dracut; break ;;
         "booster")  		pacstrap_install booster; break ;;
         "quit")     break ;;
         '')         echo -e "\nInvalid option!\n" ;;
      esac
   done

}



install_REFIND () {

	check_on_root
	mount_disk


	pacstrap_install refind 

	arch-chroot $mnt refind-install --usedefault $disk$espPart --alldrivers

	VOLUME_UUID=$(blkid $disk | awk -F\" '{ print $2 }')
	SWAP_UUID=$(blkid -s UUID -o value $disk$swapPart)
	ROOT_UUID=$(blkid -s UUID -o value $disk$rootPart)

	if [ "$rootfs" = "btrfs" ]; then
		rootflags='subvol=@'
	else
		rootflags=/
	fi

	echo "\"Boot with standard options\"  \"root=UUID=$ROOT_UUID rw rootflags=$rootflags quiet nmi_watchdog=0 loglevel=3 rd.udev.log_level=3 resume=UUID=$SWAP_UUID zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=20 zswap.zpool=z3fold\"" > $mnt/boot/refind_linux.conf
	echo "\"Boot nomodeset\"  \"root=UUID=$ROOT_UUID rw rootflags=$rootflags quiet nmi_watchdog=0 loglevel=3 rd.udev.log_level=3 resume=UUID=$SWAP_UUID zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=20 zswap.zpool=z3fold systemd.unit=multi-user.target nomodeset\"" >> $mnt/boot/refind_linux.conf
	echo "\"Boot acpi=off\"  \"root=UUID=$ROOT_UUID rw rootflags=$rootflags quiet nmi_watchdog=0 loglevel=3 rd.udev.log_level=3 resume=UUID=$SWAP_UUID zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=20 zswap.zpool=z3fold systemd.unit=multi-user.target acpi=off\"" >> $mnt/boot/refind_linux.conf
	echo "\"Boot read only\"  \"root=UUID=$ROOT_UUID ro rootflags=$rootflags quiet nmi_watchdog=0 loglevel=3 rd.udev.log_level=3 resume=UUID=$SWAP_UUID zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=20 zswap.zpool=z3fold\"" >> $mnt/boot/refind_linux.conf

#	sed -i 's/#textonly/textonly/g; s/timeout .*/timeout 3/g; s/#also_scan_dirs boot,@/also_scan_dirs +,boot,@/g; s/#scan_all_linux_kernels false/scan_all_linux_kernels false/g' $mnt$efi_path/EFI/BOOT/refind.conf

	rm -rf /boot/grub

	echo -e "\nYou should have a fully bootable system now. Feel free to test it.\n"

mkdir -p $mnt$efi_path/EFI/BOOT/
cat > $mnt$efi_path/EFI/BOOT/refind.conf <<EOF
timeout 2 
#scan_all_linux_kernels off
#also_scan_dirs +,boot,@/boot
showtools install, shell, bootorder, gdisk, memtest, mok_tool, apple_recovery, windows_recovery, about, hidden_tags, reboot, exit, firmware, fwupdate
#enable_touch
textonly
EOF


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
	mkdir -p $mnt/etc/grub.d/
	#cp $mnt/etc/grub.d/10_linux /etc/grub.d/10_linux-readonly
	#sed -i 's/\"\$title\"/\"\$title \(readonly\)\"/g' $mnt/etc/grub.d/10_linux-readonly
	#sed -i 's/ rw / ro /g' $mnt/etc/grub.d/10_linux-readonly

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
	#arch-chroot $mnt systemctl enable systemd-boot-update.service 
 	systemctl enable systemd-boot-update.service --root=/$mnt

}



general_setup () {

	check_on_root
	mount_disk


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


EOF

	[ "$root_only" -eq 0 ] && arch-chroot $mnt printf "$password\n$password\n" | passwd root

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

	arch-chroot $mnt /bin/bash -e << EOF
		printf "$password\n$password\n" | passwd user
EOF

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
export QT_LOGGING_RULES="*=false"

if [[ ! ${DISPLAY} && ${XDG_VTNR} == 1 ]]; then
	:
fi' > $mnt/home/$user/.bash_profile
	arch-chroot $mnt chown user:user /home/$user/.bash_profile

	touch $mnt/home/$user/.hushlogin
	arch-chroot $mnt chown user:user /home/$user/.hushlogin

	echo '[[ $- != *i* ]] && return
alias ls="ls --color=auto"
alias grep="grep --color=auto"
alias vi="vim"
PS1="$ "' > $mnt/home/$user/.bashrc
	arch-chroot $mnt chown user:user /home/$user/.bashrc

	cp $mnt/root/.vimrc $mnt/home/$user/.vimrc
	arch-chroot $mnt chown user:user /home/$user/.vimrc

}



setup_iwd () {

	check_on_root
	mount_disk


   setup_dhcp


	pacstrap_install iw iwd


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
	systemctl enable iwd.service --root=$mnt

}



setup_dhcp () {

	check_on_root
	mount_disk


	pacstrap_install dhcpcd


	# Helps with slow booting caused by waiting for a connection
	mkdir -p $mnt/etc/systemd/system/dhcpcd@.service.d/
	echo '[Service]
ExecStart=
ExecStart=/usr/bin/dhcpcd -b -q %I' > $mnt/etc/systemd/system/dhcpcd@.service.d/no-wait.conf

	[ "$(cat $mnt/etc/dhcpcd.conf | grep noarp)" ] && echo noarp >> $mnt/etc/dhcpcd.conf

	echo "Enabling dhcp services..."
	systemctl enable dhcpcd.service --root=$mnt

}



setup_wpa () {

	check_on_root
	mount_disk

	setup_dhcp


	pacstrap_install iw wpa_supplicant


	#arch-chroot $mnt systemctl enable wpa_supplicant.service
	systemctl enable wpa_supplicant.service --root=$mnt

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

#cmd || { printf "%b" "FAILED.\n" ; exit 1 ; }

	pacstrap_install terminus-font ncdu dosfstools parted arch-install-scripts tar man-db gptfdisk


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

	[ ! -f $mnt/usr/bin/$aur_app ] && install_aur

	# TODO: fix issue of having to change directorie permissions
	chown -R user:user /home/$user/

	if [ ! -f $mnt/usr/bin/mksh ] || [ "$reinstall" = 1 ] ; then
		arch-chroot $mnt /bin/bash << EOF
		sudo -u $user $aur_app --noconfirm -S mksh
EOF
	fi

	echo "HISTFILE=/root/.mksh_history
HISTSIZE=5000
export VISUAL=emacs
export EDITOR=/usr/bin/vim
set -o emacs" > $mnt/root/.mkshrc

   echo "HISTFILE=/home/$user/.mksh_history
HISTSIZE=5000
export VISUAL=emacs
export EDITOR=/usr/bin/vim
set -o emacs" > $mnt/home/$user/.mkshrc

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

	ESP_UUID=$(blkid -s UUID -o value $disk$espPart)

	echo '#!/usr/bin/bash

create_archive() {
            
        echo -e "Creating archive file...\n"

        cd $real_root/@/

        mksquashfs . $real_root/@/root.squashfs -noappend -no-recovery -mem-percent 20 -e root.squashfs -e boot/* -e efi/* -e dev/* -e proc/* -e sys/* -e tmp/* -e run/* -e mnt/ -e .snapshots/ -e var/tmp/* -e var/log/* -e etc/pacman.d/gnupg/ -e var/lib/systemd/random-seed

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
        new_root=/new_root
        mkdir -p $real_root $new_root

        if read -t 2 -s -n 1; then

                echo -e "\nPlease choose an option:\n\n\
<s> snapshot\n\
<w> snapshot + overlay\n\
<f> snapshot + tmpfs\n\
<o> overlay\n\
<e> squashfs + overlay\n\
<t> squashfs + tmpfs\n\
<n> create + run squashfs + overlay\n\
<r> rsync / to tmpfs\n\
<d> emergency shell\n\n\
<enter> continue boot\n"

                read -n 1 -s key



                if [[ "$key" = "s" ]] || [[ "$key" = "w" ]] || [[ "$key" = "f" ]]; then

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


                        if [[ "$key" = "f" ]]; then

                                echo "TODO!"
                                #mount -t tmpfs -o size=80% none $new_root
                                #rsync -a --exclude=root.squashfs --exclude=/efi/ --exclude=/boot/ --exclude=/dev/ --exclude=/proc/ --exclude=/sys/ --exclude=/tmp/ --exclude=/run/ --exclude=/mnt/ --exclude=/.snapshots/* --exclude=/var/tmp/ --exclude=/var/cache/ --exclude=/var/log/ /real_root/@/ $new_root
                                #umount -l /real_root

                        fi

                elif [[ "$key" = "o" ]]; then

                        mount --mkdir -o subvolid=256 ${root} $new_root

                        create_overlay

                elif [[ "$key" = "e" ]] || [[ "$key" = "n" ]] || [[ "$key" = "t" ]]; then

                                mount ${root} $real_root

                                [[ ! -f "$real_root/@/root.squashfs" ]] || [[ "$key" = "n" ]] && create_archive

                                echo "Extracting archive to RAM. Please be patient..."

                                if [ "$key" = "t" ]; then
                                        mount -t tmpfs -o size=80% none $new_root
                                        unsquashfs -d /new_root -f $real_root/@/root.squashfs
                                        echo -e "\nYou may now safely remove your USB stick.\n"
                                        sleep 1
            						  else
                                        mount "$real_root/@/root.squashfs" $new_root -t squashfs -o loop
                                        create_overlay
                                fi

                                umount -l $real_root

                elif [[ "$key" = "r" ]]; then

                        mount ${root} $real_root
                        mount -t tmpfs -o size=80% none $new_root

                        echo "Copying root filesystem to RAM. Please be patient..."

                        rsync -a --exclude=root.squashfs --exclude=/efi/ --exclude=/boot/ --exclude=/dev/ --exclude=/proc/ --exclude=/sys/ --exclude=/tmp/ --exclude=/run/ --exclude=/mnt/ --exclude=/.snapshots/* --exclude=/var/tmp/ --exclude=/var/log/ /real_root/@/ $new_root

                        echo -e "\nYou may now safely remove your USB stick.\n"
                        sleep 1

                elif [[ "$key" = "d" ]]; then

                        echo "Entering emergency shell."

                        bash

                else

                        echo "Continuing boot..."

                        umount $new_root

                        mount --mkdir -o subvolid=256 ${root} $new_root
                        mount --uuid $ESP_UUID $new_root/efi
                fi

        else

                echo -e "Running default option..."

                mount --uuid $ESP_UUID $new_root/efi

        fi

}' > $mnt/usr/lib/initcpio/hooks/liveroot


	sed -i "s/\$ESP_UUID/$ESP_UUID/g" $mnt/usr/lib/initcpio/hooks/liveroot
	cat $mnt/usr/lib/initcpio/hooks/liveroot

	echo '#!/bin/sh

build() {
	add_binary rsync
	add_binary bash
	add_binary btrfs
	add_binary unsquashfs 
	add_binary mksquashfs
	add_module overlay
	add_module loop
	add_module squashfs
	add_module vfat
	add_runscript
}

help() {
	cat << HELPEOF
Run Arch as tmpfs, overlay, squashfs, or snapshot
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
	systemctl mask systemd-remount-fs.service --root=$mnt
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

	sleep 1

	iwctl --passphrase $wifi_pass station wlan0 connect $wifi_ssid

	if [[ "$?" -eq 0 ]]; then
		echo "Connection successful!"
	else
		echo "Connection unsuccessful."
	fi

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

	rsync -av --exclude=/root.squashfs --exclude=/home/$user/.cache/ --exclude=/dev/ --exclude=/proc/ --exclude=/sys/ --exclude=/tmp/ --exclude=/run/ --exclude=/mnt/ --exclude=/.snapshots/* --exclude=/var/tmp/ --exclude=/var/log/ --exclude=/mnt/ / $mnt/

	#mkdir -p $mnt/{dev,proc,run,sys}

	setup_fstab
	install_REFIND

}



create_archive () {


	pacstrap_install squashfs-tools


	echo "Creating archive file..."

	cd / 
	rm -rf /root.squashfs

	time mksquashfs / root.squashfs -mem-percent 50 -no-recovery -noappend -e /boot/ -e /efi/ -e root.squashfs -e /dev/ -e /proc/ -e /sys -e /tmp -e /run -e /mnt -e /.snapshots/ -e /var/tmp/ -e /var/cache/ -e /var/log/ -e /etc/pacman.d/gnupg/

	ls -la root.squashfs

}



install_network () {

	echo -e "\nWhich network manager would you like to install?\n"
		
	net_choices=(iwd wpa_supplicant quit) 
	select net_choice in "${net_choices[@]}"
	do
		case $net_choice in
			"iwd")				setup_iwd; break ;;
			"dhcp")				setup_dhcp; break ;;
			"wpa_supplicant")	setup_wpa; break ;;
			"quit")				break ;;
			'')					echo -e "\nInvalid option!\n" ;;
		esac
	done

}



install_bootloader () {

	echo -e "\nWhich boot manager would you like to install?\n"

	choiceBoot=(rEFInd grub EFISTUB uki systemD quit) 
				
	select choiceBoot in "${choiceBoot[@]}"
	do
		case $choiceBoot in
			"rEFInd")	install_REFIND; break ;;
			"grub")		install_GRUB; break ;;
			"EFISTUB")	install_EFISTUB; break ;;
			"uki")		install_uki; break ;;
			"systemD")	install_SYSTEMDBOOT; break ;;
			"quit")		break ;;
			'')			echo -e "\nInvalid option!\n" ;;
		esac
	done

}



copy_script () {

	check_on_root
	mount_disk

	[ -f /arch.sh ] && cp /arch.sh $mnt/

	if [ -f $mnt/arch.sh ]; then

		echo -e "\nScript copied.\n"

		if [ "$root_only" -eq 0 ] && [ $(grep "^$user" /mnt/etc/passwd) ]; then
			arch-chroot $mnt chown $user:$user /arch.sh 
		fi

	else
		echo -e "\nScript could not be copied!!!\n"
	fi


}



install_host_packages () {

packages=("arch-install-scripts
gptfdisk
less
pactree
squashfs-tools
terminus-font
vim")

for package in $packages; do
	pacman -Qi $package &>/dev/null || pacstrap -K $mnt $package
done

}



pacstrap_install () {


	if [ "$reinstall" -eq 1 ]; then

		packages="$@"

	else

		packages=""

		for package in "$@"; do

			if [ ! "$(pacman --sysroot $mnt -Q $package 2>/dev/null)" ]; then
				packages="$package $packages"	
			else
				echo "Package: $package already installed. Not installing."
			fi

		done

	fi

	if [ "$packages" ]; then

		if [ "$offline" -eq 1 ]; then
			#pacstrap -C /etc/pacman-offline.conf -c -K $mnt ${packages[@]}
			pacstrap -C /etc/pacman-offline.conf -c $mnt ${packages[@]}
		else
			pacstrap -C /etc/pacman.conf -c -K $mnt "$@"
		fi

	fi

}



finalize_install () {

	[ "$offline" -eq 0 ] && arch-chroot $mnt pacman -Syu

	packages="$(pacman --sysroot $mnt -Q | sed 's/ [0-9].*$//g')"

	for package in ${packages}; do

		echo "Copying $package..."
		cp -u /var/cache/pacman/pkg/$package* $mnt/var/cache/pacman/pkg/

	done

	echo -e "\nUpdating package database. Please be patient...\n"
	repo-add -q -n $mnt/var/cache/pacman/pkg/./custom.db.tar.gz $mnt/var/cache/pacman/pkg/*.zst

	pacman-db-upgrade

	copy_script

	echo "Syncing..."
	sync

}



check_online () {

	ping -q -w 1 -c 1 $(ip r | grep default | cut -d ' ' -f 3) > /dev/null || offline=1 

	if [ "$offline" -eq 1 ]; then
		echo -e "\nNo internet connection found. Offline mode enabled."
	fi
}



auto_install_root () {

	root_only=1

	create_partitions
	install_base
	setup_fstab
	install_REFIND
	general_setup
	setup_iwd
	install_liveroot
	finalize_install	

}



auto_install_user () {

	root_only=0

	create_partitions
	install_base
	setup_fstab
	install_REFIND
	general_setup
	setup_user
	setup_iwd
	install_liveroot
	finalize_install	

}


if [ "$1" ]; then
	disk="$1"
else
	choose_disk
fi

check_viable_disk
check_online

if [ "$offline" -eq 1 ]; then
	echo -e "\nInitializing repo for offline installation..."
fi


loadkeys en

# Make font big and readable
if [ -f /usr/share/kbd/consolefonts/ter-132b.psf.gz ]; then
	setfont ter-132b
fi



choices=("1. Quit
2. Chroot
3. Choose disk
4. Partition disk
5. Install base
6. Hypervisor setup
7. Setup fstab
8. Install boot manager
9. General setup
10. Setup user
11. Setup network
12. Install aur
13. Install tweaks
14. Install mksh
15. Install liveroot
16. Setup snapshots
17. Setup snapper
18. Mount $mnt
19. Unmount $mnt
20. Create squashfs image
21. Clone disk
22. Connect wireless
23. Download script
24. Install host packages
25. Reset pacman keys
27. Finalize install
28. Auto-install (root)
29. Auto-install (user)
30. Copy scripts
31. Choose initramfs")


while :; do

echo
echo "${choices[@]}" | column   
echo  

read -p "Which option? " choice

	case $choice in
		Quit|quit|q|exit|1)	break; ;;
		Chroot|chroot|2)		do_chroot ;;
		disk|3)					choose_disk ;;
		partition|4)			create_partitions ;;
		base|5)					install_base ;;
		hypervisor|6)			hypervisor_setup ;;
		fstab|7)					setup_fstab ;;
		boot|8)					install_bootloader ;;
		setup|9)					general_setup ;;
		user|10)					setup_user ;;
      network|11)				install_network ;;
		aur|12)					install_aur ;;
		tweaks|13)				install_tweaks ;;
      mksh|14)					install_mksh ;;
		liveroot|15)			install_liveroot ;;
		snapshots|16)			setup_snapshots ;;
		snapper|17)				setup_snapper ;;
      mount|18)				mount_disk  ;;
      unmount|19)				unmount_disk  ;;
		squashfs|20)			create_archive ;;
		clone|21)				clone_disk ;;
		connect|iwd|22)		connect_wireless ;;
		script|23)				download_script ;;
		host|24)			 		install_host_packages ;;
		reset|keys|25)			reset_keys ;;
		finalize|27)			finalize_install ;;
		root|28)					time auto_install_root ;;
		user|29)					time auto_install_user ;;
		copy_script|30)		copy_script ;;
		initramfs|31)			choose_initramfs ;;
		*)							echo -e "\nInvalid option ($choice)!\n"; ;;
	esac

done

unmount_disk


