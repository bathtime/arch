#!/bin/bash

# ext4 on ssd

#rm -rf tempfile; dd if=/dev/zero of=tempfile bs=4M count=4096 conv=fdatasync,notrunc
#17179869184 bytes (17 GB, 16 GiB) copied, 10.9708 s, 1.6 GB/s

#rm -rf tempfile; dd if=/dev/zero of=tempfile bs=512 count=1000000 conv=fdatasync,notrunc
#512000000 bytes (512 MB, 488 MiB) copied, 2.09522 s, 244 MB/s

#Startup finished in 1.834s (firmware) + 1.557s (loader) + 3.517s (kernel) + 1.469s (userspace) = 8.378s - 3s
#graphical.target reached after 1.461s in userspace.



# btrfs on ssd


#dd if=/dev/zero of=tempfile bs=4M count=4096 conv=fdatasync,notrunc
#17179869184 bytes (17 GB, 16 GiB) copied, 13.5097 s, 1.3 GB/s

#dd if=/dev/zero of=tempfile bs=512 count=1000000 conv=fdatasync,notrunc
#512000000 bytes (512 MB, 488 MiB) copied, 3.49716 s, 146 MB/s

#Startup finished in 1.864s (firmware) + 3.116s (loader) + 3.486s (kernel) + 1.473s (userspace) = 9.941s 
#graphical.target reached after 1.457s in userspace.


#xfs on ssd
# install 3 minutes
#Startup finished in 3.477s (firmware) + 1.561s (loader) + 3.742s (kernel) + 1.487s (userspace) = 10.269s 
#graphical.target reached after 1.474s in userspace.


#ext4 install on flash 11:15: boot 19.1 seconds: rm -rf tempfile; dd if=/dev/zero of=tempfile bs=1M count=1024 conv=fdatasync,notrunc = 14.4 MB/s

# xfs install on flash 13:07 mins: boot in 18.8s: rm -rf tempfile; dd if=/dev/zero of=tempfile bs=1M count=1024 conv=fdatasync,notrunc = 17.3 MB/s

# btrfs install on flash 13:03: boot in 17s: rm -rf tempfile; dd if=/dev/zero of=tempfile bs=1M count=1024 conv=fdatasync,notrunc = 15.3 MB/s

# jfs install on flash 17:32: boot in 22s: rm -rf tempfile; dd if=/dev/zero of=tempfile bs=1M count=1024 conv=fdatasync,notrunc = 16 MB/s 

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

	echo -e "\e[0;41m\n\nFile: \e[1;2;41m$1\n\e[0;41mError: \e[1;2;41m$3\n\e[0;41mLine:\e[1;2;41m $2\n\e[0;41mCommand:\e[1;2;41m $4\n\e[0;29m\n"

	finished=0

	while [ $finished -eq 0 ]; do

		echo -e "What now?\n\n[e] edit (last position)\n[n] edit (error position)\n[c] continue\n[x] exit\n"

		read -p "Choice: " -n 2 choice

		case $choice in
				e)		vim $arch_path/$arch_file; exit ;;
				n)		vim +$2 $arch_path/$arch_file; exit ;;
				c)		set +e; break ;;
				x)		exit ;;
				*) 	finished=0 ;;
		esac

	done

}

trap 'error "${BASH_SOURCE}" "${LINENO}" "$?" "${BASH_COMMAND}"' ERR
trap 'echo;echo; read -s -r -n 1 -p "<ctrl> + c pressed. Press any key to continue... "; set +e' SIGINT



error_check () {

	if [ $1 -eq 1 ]; then
		set -Eeo pipefail
	else
		set +e 
	fi

}

# Used to temporarily disable at certain points in script (eg., as in the mount_disk function)
error_check 1


arch_file=$(basename "$0")
arch_path=$(dirname "$0")

mnt=/mnt
espPartNum=1
bootPartNum=2
swapPartNum=3
rootPartNum=4
espPart=$espPartNum
bootPart=$bootPartNum
swapPart=$swapPartNum
rootPart=$rootPartNum
fstype='bcachefs'		# ext4,btrfs,xfs,jfs,bcachefs,f2fs
bootPartType='ext4'
subvols=()
efi_path=/efi
boot_path=/boot
encrypt=true

kernel_ops="quiet nmi_watchdog=0 nowatchdog modprobe.blacklist=iTCO_wdt mitigations=off loglevel=3 rd.udev.log_level=3 zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=20 zswap.zpool=z3fold"

# systemd.gpt_auto=0

user=user
password=123456
aur_app=paru
aur_path=/home/$user

ucode=intel-ucode
hostname=Arch
timezone=Canada/Eastern

offline=0
reinstall=0
root_only=0
copy_on_host=1

initramfs=mkinitcpio

wifi_ssid="BELL364"
wifi_pass="13FDC4A93E3C"

dirty_threshold=0


check_pkg () {


	if [ ! "$(pacman -Q $1)" ]; then
		echo -e "\nInstalling program required to run command: $1...\n"
		pacman --noconfirm -S $1
		echo
	fi

}


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

	sync_disk

	error_check 0 
		
	if [[ $(mount | grep -E $disk$espPart | grep -E "on $mnt$efi_path") ]]; then
		echo "Unmounting $mnt$efi_path..."
		umount -n -R $mnt$efi_path
		sleep .1

	fi

	if [[ $(mount | grep -E $disk$rootPart | grep -E "on $mnt") ]]; then

		# Might need to turn error checking off here

		echo "Unmounting $mnt..."

		# Shouldn't be in directory we're unmounting   
		[[ "$(pwd | grep $mnt)" ]] && cd ..

		umount -n -R $mnt

		# Time to get rugged and tough!
		if [[ "$(mount | grep /mnt)" ]]; then

			echo -e "\nCouldn't unmount. Trying alternative method. Please be patient...\n" 

			mounted=1

			while [[ "$mounted" -eq 1 ]]; do
				
				cd /

				if [[ "$(mount | grep /mnt)" ]]; then
					sleep 2
					umount -l $mnt
				else
					mounted=0
				fi

			done

			echo -e "\nLazy unmount successful.\n"
			systemctl daemon-reload

		fi

	else
		echo -e "\nDisk already unmounted!\n"
	fi

	error_check 1

}



choose_disk () {

	search_disks=1
	host="$(mount | awk '/ on \/ / { print $1}' | sed 's/p*[0-9]$//g')"

	while [ $search_disks -eq 1 ]; do

		echo -e "\nDrives found:\n"

		lsblk --output=PATH,SIZE,MODEL,TRAN -d | grep -P "/dev/sd|nvme|vd" | sed "s#$host.*#& (host)#g"
		disks=$(lsblk -dpnoNAME|grep -P "/dev/sd|nvme|vd") 
		disks=$(echo -e "\nquit\nedit\n$\n#\n$disks\n/\nupdate\nrefresh\nreboot\nsuspend\nhibernate\npoweroff\nhtop")

		echo -e "\nWhich drive?\n"

		select disk in $disks
		do
			case $disk in
				$)				sudo -u $user bash ;;
				\#)				bash ;;
				update)		pacman -Syu --noconfirm ;;
				/)				disk=$host; search_disks=0 ; break ;;
				refresh) 	break;	;;
				poweroff)	poweroff ;;
				suspend)		echo mem > /sys/power/state ;;
				hibernate)	echo disk > /sys/power/state ;;
				htop)			su - user -c /usr/bin/htop ;;
				reboot)		reboot ;;
				quit) 		echo -e "\nQuitting!"; exit ;;
				edit)			vim $arch_path/$arch_file; exit ;;
				'')   		echo -e "\nInvalid option!\n" ; break ;;
				*)    		search_disks=0; break; ;;
			esac
		done

	done

	if [ "$(echo $disk | grep nvme)" ]; then
		espPart="p$espPartNum"
		bootPart="p$bootPartNum"
		swapPart="p$swapPartNum"
		rootPart="p$rootPartNum"
	fi

}



delete_partitions () {

	check_on_root
	unmount_disk

	echo -e "\nWiping disk...\n"

	wipefs -af $disk

	check_pkg gptfdisk

	sgdisk -Zo $disk

}



create_partitions () {

	check_on_root
	delete_partitions
	
	systemctl daemon-reload

	check_pkg parted
	
	parted -s $disk mklabel gpt \
			mkpart ESP fat32 1Mib 512Mib \
			set $espPartNum esp on \
			mkpart BOOT $bootPartType 512Mib 2048Mib \
			mkpart SWAP linux-swap 2048Mib 10048Mib \
			set $swapPartNum swap on \

	
	if [ "$fstype" = "bcachefs" ]; then
		parted -s $disk mkpart ROOT ext4 10048Mib 100%
	else
		parted -s $disk mkpart ROOT $fstype 10048Mib 100%
	fi

	check_pkg dosfstools

	mkfs.fat -F 32 -n EFI $disk$espPart 
	mkfs.ext4 -F -q -t ext4 -L BOOT $disk$bootPart
	mkswap -L SWAP $disk$swapPart

	case $fstype in

		btrfs)		check_pkg btrfs-progs
						mkfs.btrfs -f -L ROOT $disk$rootPart

						echo -e "\nMounting $mnt..."
						mount --mkdir $disk$rootPart $mnt

						cd $mnt

						for subvol in '' "${subvols[@]}"; do
							btrfs su cr /mnt/@"$subvol"
						done
	
						unmount_disk ;;

		ext4)			mkfs.ext4 -F -q -t ext4 -L ROOT $disk$rootPart 
						echo "Using tune2fs to create fast commit journal area. Please be patient..." 
						tune2fs -O fast_commit $disk$rootPart
						tune2fs -l $disk$rootPart | grep features ;;
		xfs)			check_pkg xfsprogs			
						mkfs.xfs -f -L ROOT $disk$rootPart ;;
		jfs)			check_pkg jfsutils			
						mkfs.jfs -f -L ROOT $disk$rootPart ;;
		f2fs)			check_pkg f2fs-tools
						mkfs.f2fs -f -l ROOT $disk$rootPart ;;
		bcachefs)	check_pkg bcachefs-tools
	               if [ "$encrypt" = "true" ]; then
                     bcachefs format --encrypted --compression=lz4 -f -L ROOT $disk$rootPart
      					#bcachefs unlock -k session $disk$rootPart
							#unmount_disk
                  else
                     bcachefs format -f -L ROOT $disk$rootPart
                  fi
                  ;;
esac

	parted -s $disk print

	mount_disk

}



mount_disk () {

	fstype="$(lsblk -n -o FSTYPE $disk$rootPart)"
echo "File type: $fstype"
	error_check 0
	check_on_root

	if [[ ! $(mount | grep -E $disk$rootPart | grep -E "on $mnt") ]]; then


		if [ "$fstype" = "btrfs" ]; then

			echo -e "\nMounting...\n"

			#mountopts="nodatacow,nodatasum,noatime,compress-force=zstd:1,discard=async"
			#mountopts="nodatacow,nodatasum,noatime,discard=async"
			mountopts="noatime,discard=async"

			for subvol in '' "${subvols[@]}"; do
				mount --mkdir -o "$mountopts",subvol=@"$subvol" $disk$rootPart $mnt/"${subvol//_//}"
			done

		else

			if [ "$fstype" = "bcachefs" ] && [ "$encrypt" = "true" ]; then
      		bcachefs unlock -k session $disk$rootPart
			fi

			mount --mkdir $disk$rootPart $mnt

   	fi

	fi
	
	if [[ ! $(mount | grep -E $disk$espPart | grep -E "on $mnt$efi_path") ]]; then
		mount --mkdir $disk$espPart $mnt$efi_path
	fi

	if [[ ! $(mount | grep -E $disk$bootPart | grep -E "on $mnt$boot_path") ]]; then
		mount --mkdir $disk$bootPart $mnt$boot_path
	fi

	mkdir -p $mnt/{etc,tmp,root,var/cache/pacman/pkg,/var/tmp,/var/log}
	
	if [ "$fstype" = "btrfs" ]; then
		#mkdir -p $mnt/.snapshots
		chattr +C -R $mnt/tmp
		chattr +C -R $mnt/var/tmp
		chattr +C -R $mnt/var/log
	fi

	chmod 750 $mnt/root


	error_check 1

}



install_base () {

	check_on_root
	mount_disk
	
	echo '[options]
HoldPkg     = pacman glibc
Architecture = auto

CheckSpace
ParallelDownloads = 1
Color

[custom]
SigLevel = Optional TrustAll
Server = file:///var/cache/pacman/pkg/
' > /etc/pacman-offline.conf
	cp /etc/pacman-offline.conf $mnt/etc/pacman-offline.conf


	if [ "$offline" -eq 1 ]; then
		echo "Copying database files..."
		mkdir -p $mnt/var/lib/pacman/sync
		cp -r /var/lib/pacman/sync/*.db $mnt/var/lib/pacman/sync/
	fi

	reset_keys

	check_pkg arch-install-scripts

	packages="base linux linux-firmware vim parted gptfdisk arch-install-scripts pacman-contrib tar man-db dosfstools"
	#packages="linux vi arch-install-scripts pacman-contrib tar man-db"

	[ "$root_only" ] && packages="$packages sudo"

	if [ "$fstype" = "btrfs" ]; then
		packages="$packages btrfs-progs grub-btrfs"
	fi
	[ "$fstype" = "xfs" ] && packages="$packages xfsprogs"
	[ "$fstype" = "jfs" ] && packages="$packages jfsutils"
	[ "$fstype" = "f2fs" ] && packages="$packages f2fs-tools"
	[ "$fstype" = "bcachefs" ] && packages="$packages bcachefs-tools"

	pacstrap_install $packages

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

		kvm)			pacstrap_install qemu-guest-agent
						systemctl --root=$mnt enable qemu-guest-agent ;;
		vmware)		pacstrap_install open-vm-tools
						systemctl --root=$mnt enable vmtoolsd
						systemctl --root=$mnt enable vmware-vmblock-fuse ;;
		oracle)		pacstrap_install virtualbox-guest-utils
						systemctl --root=$mnt enable vboxservice ;;
		microsoft)	pacstrap_install hyperv
						systemctl --root=$mnt enable hv_fcopy_daemon
						systemctl --root=$mnt enable hv_kvp_daemon
						systemctl --root=$mnt enable hv_vss_daemon ;;
	esac

}



setup_fstab () {

	check_on_root
	mount_disk

	echo -e "\nCreating new /etc/fstab file...\n"

	genfstab -U $mnt > $mnt/etc/fstab


	###  Tweak the resulting /etc/fstab generated  ###

	SWAP_UUID=$(blkid -s UUID -o value $disk$swapPart)

	# Changing compression
	sed -i 's/zstd:3/zstd:1/' $mnt/etc/fstab

	# Bad idea to use subids when rolling back 
	sed -i 's/subvolid=.*,//g' $mnt/etc/fstab

	# genfstab will generate a swap drive. we're using a swap file instead
	#sed -i '/LABEL=SWAP/d; /none.*swap.*defaults/d' $mnt/etc/fstab

	#sed -i 's/relatime/noatime/g' $mnt/etc/fstab

	sed -i 's/\/.*ext4.*0 1/\/      ext4    rw,noatime,commit=60      0 1/' $mnt/etc/fstab

	# Make /efi read-only
	#sed -i 's/\/efi.*vfat.*rw/\/efi     vfat     ro/' $mnt/etc/fstab

#	[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /var/cache')" ] && echo "tmpfs    /var/cache  tmpfs   rw,nodev,nosuid,mode=1755,size=2G   0 0" >> $mnt/etc/fstab
	#[ ! "$(cat $mnt/etc/fstab | grep 'none swap defaults 0 0')" ] && echo -e "UUID=$SWAP_UUID none swap defaults 0 0\n" >> $mnt/etc/fstab
	#[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /var/log')" ]   && echo "tmpfs    /var/log    tmpfs   rw,nodev,nosuid,mode=1775,size=2G   0 0" >> $mnt/etc/fstab
	#[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /var/tmp')" ]   && echo "tmpfs    /var/tmp    tmpfs   rw,nodev,nosuid,mode=1777,size=2G   0 0" >> $mnt/etc/fstab
	#[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /home/user/.cache')" ]   && echo "tmpfs    /home/user/.cache    tmpfs  rw,size=1G,nr_inodes=5k,noexec,nodev,nosuid,uid=user,mode=1777 0 0" >> $mnt/etc/fstab
	systemctl daemon-reload

	cat $mnt/etc/fstab

}



choose_initramfs () {

	if [ "$1" ]; then
		choiceInitramfs=$1
	else
		choiceInitramfs="mkinitcpio dracut booster quit"
		echo -e "\nWhich initramfs would you like to install?"
	fi

	select choice in $choiceInitramfs
	do
		case $choice in
			mkinitcpio|1)	pacstrap_install mkinitcpio; break ;;
			dracut|2)		pacstrap_install dracut; break ;;
			booster|3)		pacstrap_install booster; break ;;
			quit|4)			break ;;
			'')				echo -e "\nInvalid option!\n" ;;
		esac
	done

}



install_REFIND () {

	check_on_root
	mount_disk


	pacstrap_install refind 
	

	mkdir -p $mnt/{proc,sys,dev,run}

	arch-chroot $mnt refind-install --usedefault $disk$espPart --alldrivers

	VOLUME_UUID=$(blkid $disk | awk -F\" '{ print $2 }')
	SWAP_UUID=$(blkid -s UUID -o value $disk$swapPart)
	ROOT_UUID=$(blkid -s UUID -o value $disk$rootPart)

	if [ "$fstype" = "btrfs" ]; then
		rootflags='rootflags=subvol=@'
	else
		rootflags=''
	fi


	echo "\"Boot with standard options\"  \"root=UUID=$ROOT_UUID rw $rootflags $kernel_ops resume=UUID=$SWAP_UUID\"" > $mnt/boot/refind_linux.conf
	echo "\"Boot nomodeset\"  \"root=UUID=$ROOT_UUID rw $rootflags $kernel_ops resume=UUID=$SWAP_UUID systemd.unit=multi-user.target nomodeset\"" >> $mnt/boot/refind_linux.conf
	echo "\"Boot acpi=off\"  \"root=UUID=$ROOT_UUID rw $rootflags $kernel_ops resume=UUID=$SWAP_UUID systemd.unit=multi-user.target acpi=off\"" >> $mnt/boot/refind_linux.conf
	echo "\"Boot read only\"  \"root=UUID=$ROOT_UUID ro $rootflags $kernel_ops resume=UUID=$SWAP_UUID\"" >> $mnt/boot/refind_linux.conf
	echo "\"Boot no options\"  \"root=UUID=$ROOT_UUID rw $rootflags resume=UUID=$SWAP_UUID\"" >> $mnt/boot/refind_linux.conf

#	sed -i 's/#textonly/textonly/g; s/timeout .*/timeout 3/g; s/#also_scan_dirs boot,@/also_scan_dirs +,boot,@/g; s/#scan_all_linux_kernels false/scan_all_linux_kernels false/g' $mnt$efi_path/EFI/BOOT/refind.conf

	mkdir -p $mnt$efi_path/EFI/BOOT/
cat > $mnt$efi_path/EFI/BOOT/refind.conf <<EOF
timeout 2 
#scan_all_linux_kernels off
#also_scan_dirs +,boot,@/boot
showtools install, shell, bootorder, gdisk, memtest, mok_tool, about, hidden_tags, reboot, exit, firmware, fwupdate
#enable_touch
textonly
EOF

	rm -rf /boot/grub

	echo -e "\nYou should have a fully bootable system now. Feel free to test it.\n"

}



install_GRUB () {

	check_on_root
	mount_disk


	pacstrap_install grub os-prober efibootmgr inotify-tools lz4

	#if [ "$fstype" = "btrfs" ]; then
	#	pacstrap_install grub-btrfs
	#fi

	SWAP_UUID=$(blkid -s UUID -o value $disk$swapPart)

	arch-chroot $mnt /bin/bash -e << EOF

	grub-install --target=x86_64-efi --efi-directory=$efi_path --bootloader-id=GRUB --removable

	cat > /etc/default/grub << EOF2

GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=""
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="$kernel_ops resume=UUID=$SWAP_UUID"
GRUB_DISABLE_RECOVERY="true"
GRUB_HIDDEN_TIMEOUT=1
GRUB_RECORDFAIL_TIMEOUT=1
GRUB_TIMEOUT=0
 
# Update grub with:
# grub-mkconfig -o /boot/grub/grub.cfg

EOF2


	# Allows grub to run snapshots
	#if [ "$fstype" = "btrfs" ]; then
	#	systemctl --root=$mnt enable grub-btrfsd.service
	#	/etc/grub.d/41_snapshots-btrfs
	#fi

	# Remove grub os-prober message
	sed -i 's/grub_warn/#grub_warn/g' /etc/grub.d/30_os-prober



	###  Offer readonly grub booting option  ###
	mkdir -p /etc/grub.d/
	cp /etc/grub.d/10_linux /etc/grub.d/10_linux-readonly
	sed -i 's/\"\$title\"/\"\$title \(readonly\)\"/g' /etc/grub.d/10_linux-readonly
	sed -i 's/ rw / ro /g' /etc/grub.d/10_linux-readonly

	cp /etc/grub.d/10_linux /etc/grub.d/10_linux-nomodeset
	sed -i 's/\"\$title\"/\"\$title \(nomodeset\)\"/g' /etc/grub.d/10_linux-nomodeset
	sed -i 's/ rw / rw nomodeset /g' /etc/grub.d/10_linux-nomodeset


	grub-mkconfig -o /boot/grub/grub.cfg

EOF

	# So systemd won't remount as 'rw'
	#systemctl --root=$mnt mask systemd-remount-fs.service

	echo -e "\nYou should have a fully bootable system now. Feel free to test it.\n"

}


install_EFISTUB () {

	echo "TODO."

	return 0

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

	return 0	

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

	#rm -rf $mnt/var/tmp && ln -s $mnt/tmp $mnt/var/tmp

	arch-chroot $mnt printf "$password\n$password\n" | passwd
	
	echo -e 'en_US.UTF-8 UTF-8\nen_US ISO-8859-1' > $mnt/etc/locale.gen  
	echo 'LANG=en_US.UTF-8' > $mnt/etc/locale.conf
	echo 'Arch-Linux' > $mnt/etc/hostname
	echo 'KEYMAP=us' > $mnt/etc/vconsole.conf
	arch-chroot $mnt ln -sf /usr/share/zoneinfo/$timezone /etc/localtime

	echo "127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname" > $mnt/etc/hosts

	echo '[[ $- != *i* ]] && return
alias ls="ls --color=auto"
alias grep="grep --color=auto"
alias vi="vim"
alias arch="sudo /usr/local/bin/arch.sh"
PS1="# "' > $mnt/root/.bashrc

	arch-chroot $mnt hwclock --systohc
	arch-chroot $mnt locale-gen

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

	if [ "$(grep -c "^$user" $mnt/etc/passwd)" -eq 0 ]; then
		arch-chroot $mnt useradd -m $user -G wheel
	fi
	
	if [ "$fstype" = "btrfs" ]; then
		mkdir -p $mnt/home/$user/.cache
		chown -R $user:$user $mnt/home/$user/.cache
		chattr +C -R $mnt/home/$user/.cache
	fi


	if [ "$(grep -c "^$user" $mnt/etc/passwd)" -eq 0 ]; then
		echo -e "\nUser was not created. Exiting.\n"
		exit
	fi

	arch-chroot $mnt /bin/bash -e << EOF
		printf "$password\n$password\n" | passwd "$user"
EOF


	#rm -rf $mnt/home/$user/.cache
	#sudo -u $user ln -s $mnt/run/user/1000/ $mnt/home/$user/.cache


	mkdir -p -m 750 $mnt/etc/sudoers.d
	echo '%wheel ALL=(ALL:ALL) ALL' > $mnt/etc/sudoers.d/1-wheel
	echo "$user ALL = NOPASSWD: /usr/local/bin/arch.sh" > $mnt/etc/sudoers.d/10-arch
	chmod 0440 $mnt/etc/sudoers.d/{1-wheel,10-arch}

	arch-chroot $mnt visudo -c
	
	# Autologin to tty1
	mkdir -p $mnt/etc/systemd/system/getty@tty1.service.d
	echo "[Service]
Type=simple
ExecStart=
ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin $user --noclear %I 38400 linux" > $mnt/etc/systemd/system/getty@tty1.service.d/autologin.conf

	#[ ! "$(cat $mnt/etc/fstab | grep 'tmpfs    /home/user/.cache')" ] && echo "tmpfs    /home/user/.cache    tmpfs   rw,nodev,nosuid,uid=$user,size=2G   0 0" >> $mnt/etc/fstab

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
alias arch="sudo /usr/local/bin/arch.sh"
PS1="$ "' > $mnt/home/$user/.bashrc
	arch-chroot $mnt chown user:user /home/$user/.bashrc

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

	cp $mnt/root/.vimrc $mnt/home/$user/.vimrc
	arch-chroot $mnt chown $user:$user /home/$user/.vimrc

}



setup_iwd () {

	check_on_root
	mount_disk


   setup_dhcp


	pacstrap_install iw iwd
	
	mkdir -p $mnt/etc/iwd $mnt/var/lib/iwd
	echo '[1901eb9f-5672-5518-b900-ee43811a3672]
name=/var/lib/iwd//BELL364.psk
list= 5220 5805 2462' > $mnt/var/lib/iwd/.known_network.freq 
 
	echo '[Security]
PreSharedKey=14ad650cdc57e587a5198d3be78cb4ef4dc2574a580949d3b9803774858c5abd
Passphrase=13FDC4A93E3C
SAE-PT-Group19=f5614183429496736ed0da01f20d14b3415e201531b6fc24987eb128c2090897dcb358dc0eac4716994f6dee52bd7cb642bc67f43106478fded1236655418a7a
SAE-PT-Group20=eb986ca0245dcd12c86bf779e36d4434973059133f10e12326cf319db32b98fed48e248f69e015bed36813f716581e13d56a21dbbda4fe3541e355afe49446458e8d8e47777b9866f720197effd6273b6e89cbdc140e58920cf269abe6ea0bf7' > $mnt/var/lib/iwd/BELL364.psk 

	echo '[General]
EnableNetworkConfiguration=true

[Scan]
DisablePeriodicScan=true' > $mnt/etc/iwd/main.conf

	echo "Enabling network services..."
	systemctl --root=$mnt enable iwd.service

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
	systemctl --root=$mnt enable dhcpcd.service

}



setup_wpa () {

	check_on_root
	mount_disk

	setup_dhcp


	pacstrap_install iw wpa_supplicant


	systemctl --root=$mnt enable wpa_supplicant.service

	mkdir -p $mnt/etc/wpa_supplicant
	arch-chroot $mnt wpa_passphrase "$wifi_ssid" "$wifi_pass" > $mnt/etc/wpa_supplicant/"$wifi_ssid".conf

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

acpid () {

		echo '[Unit]
Description=AC user power service

[Service]
ExecStart=/home/user/.local/bin/power.sh

[Install]
WantedBy=multi-user.target' > $mnt/etc/systemd/system/user-power.service

	ln -s $mnt/etc/systemd/system/user-power.service $mnt/etc/systemd/system/multi-user.target.wants/user-power.service


# Needs to be reimplimented after hibernation

echo '#!/bin/sh

case $1/$2 in
  pre/*)
    echo "Going to $2..."
    ;;
  post/*)
    echo "Waking up from $2..."
         echo 85 > /sys/class/power_supply/BAT0/charge_control_end_threshold
    ;;
esac' > $mnt/usr/lib/systemd/system-sleep/sleep.sh 



	pacstrap_install pacman -S acpid

	# TODO find a way to activate sysd service
	arch-chroot $mnt systemctl enable acpid.service

	echo 'SUBSYSTEM=="power_supply", ATTR{online}=="0", RUN+="/home/user/.local/bin/pluggedin.sh false"
SUBSYSTEM=="power_supply", ATTR{online}=="1", RUN+="/home/user/.local/bin/pluggedin.sh true"' > $mnt/etc/udev/rules.d/powersave.rules

echo '[Unit]
Description=ACPI event daemon
Documentation=man:acpid(8)

[Service]
ExecStart=/usr/bin/acpid --foreground --netlink

[Install]
WantedBy=multi-user.target' > $mnt/usr/lib/systemd/system/acpid.service

	# Manually enable it
	ln -s $mnt/usr/lib/systemd/system/acpid.service $mnt/etc/systemd/system/multi-user.target.wants/acpid.service

}


install_tweaks () {

	check_on_root
	mount_disk

	
	#pacstrap_install terminus-font ncdu

	#[ ! $(cat $mnt/etc/vconsole.conf | grep 'FONT=ter-132b') ] && echo 'FONT=ter-132b' >> $mnt/etc/vconsole.conf


	echo 'vm.swappiness = 10' > $mnt/etc/sysctl.d/99-swappiness.conf
	echo 'vm.vfs_cache_pressure=50' > $mnt/etc/sysctl.d/99-cache-pressure.conf
	echo 'net.ipv4.tcp_fin_timeout = 30' > $mnt/etc/sysctl.d/99-net-timeout.conf
	echo 'net.ipv4.tcp_keepalive_time = 120' > $mnt/etc/sysctl.d/99-net-keepalive.conf
	

	systemctl --root=$mnt enable systemd-oomd

	echo 'kernel.core_pattern=/dev/null' > $mnt/etc/sysctl.d/50-coredump.conf

	mkdir -p $mnt/etc/systemd/coredump.conf.d/
	echo '[Coredump]
Storage=none
ProcessSizeMax=0' > $mnt/etc/systemd/coredump.conf.d/custom.conf

	echo '* hard core 0' > $mnt/etc/security/limits.conf

}



install_mksh () {

	[ ! -f $mnt/usr/bin/$aur_app ] && install_aur

	# TODO: fix issue of having to change directory permissions
	arch-chroot $mnt chown -R $user:$user /home/$user/

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
	arch-chroot $mnt chown $user:$user /home/$user/.mkshrc

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
	arch-chroot $mnt chown $user:$user /home/$user/.profile 

	arch-chroot $mnt /bin/bash << EOF
chsh -s /usr/bin/mksh                          # root shell
echo 123456 | sudo -u $user chsh -s /bin/mksh  # user shell
EOF

}


install_timeshift () {

  	pacstrap_install timeshift xorg-xhost

	cp $mnt/usr/share/applications/timeshift-gtk.desktop $mnt/home/$user/.local/share/applications/

	# Required to start the application under wayland
	var='pkexec env $(env) timeshift-launcher'
	sed -i "s/Exec=.*$/Exec=$var/" $mnt/home/$user/.local/share/applications/timeshift-gtk.desktop

}


install_liveroot () {

	check_on_root
	mount_disk

	touch $mnt/etc/vconsole.conf

	pacstrap_install rsync squashfs-tools

   echo '#!/usr/bin/bash

   #fstype="ext4"
   fsroot=""

create_archive() {
            
   echo -e "Creating archive file...\n"

   cd $real_root/"$fsroot"
   mksquashfs . $real_root/"$fsroot"root.squashfs -noappend -no-recovery -mem-percent 20 -e root.squashfs -e boot/* -e efi/* -e dev/* -e proc/* -e sys/* -e tmp/* -e run/* -e mnt/ -e .snapshots/ -e var/tmp/* -e var/log/* -e etc/pacman.d/gnupg/ -e var/lib/systemd/random-seed
   ls -lah $real_root/"$fsroot"root.squashfs

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

   disk=$(mount | grep " on /new_root " | sed "s/[0-9] on \/new_root.*//g")
	fs_type=$(mount | grep " on /new_root " | sed "s/^.*type //;s/ (.*$//")

	root_part=$(blkid | grep ROOT | sed "s/:.*$//")

   ESP_UUID=$(blkid -s UUID -o value $disk"1")

			if [ "$fs_type" = "btrfs" ]; then
   			fsroot="@/"
				echo "Mounting $fs_type with $fsroot..."
			fi

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
                                #mount -t tmpfs -o size=60% none $new_root
                                #rsync -a --exclude=root.squashfs --exclude=/efi/ --exclude=/boot/ --exclude=/dev/ --exclude=/proc/ --exclude=/sys/ --exclude=/tmp/ --exclude=/run/ --exclude=/mnt/ --exclude=/.snapshots/* --exclude=/var/tmp/ --exclude=/var/cache/ --exclude=/var/log/ /real_root/@/ $new_root
                                #umount -l /real_root

                        fi

                elif [[ "$key" = "o" ]]; then

                        if [ "$fstype" = "btrfs" ]; then
                                mount --mkdir -o subvolid=256 ${root} $new_root
                        fi

                        create_overlay

                elif [[ "$key" = "e" ]] || [[ "$key" = "n" ]] || [[ "$key" = "t" ]]; then

                        mount ${root} $real_root

                        [[ ! -f "$real_root/"$fsroot"root.squashfs" ]] || [[ "$key" = "n" ]] && create_archive

                        echo "Extracting archive to RAM. Please be patient..."

                        if [ "$key" = "t" ]; then
                                mount -t tmpfs -o size=80% none $new_root
                                unsquashfs -d /new_root -f $real_root/"$fsroot"root.squashfs
                                echo -e "\nYou may now safely remove your USB stick.\n"
                                sleep 1
                        else
                                mount "$real_root/"$fsroot"root.squashfs" $new_root -t squashfs -o loop
                                create_overlay
                        fi

                        umount -l $real_root

                elif [[ "$key" = "r" ]]; then

                        mount ${root} $real_root
                        mount -t tmpfs -o size=80% none $new_root

                        echo "Copying root filesystem to RAM. Please be patient..."

                        rsync --info=progress2 -a --exclude=root.squashfs --exclude=/efi/ --exclude=/boot/ --exclude=/dev/ --exclude=/proc/ --exclude=/sys/ --exclude=/tmp/ --exclude=/run/ --exclude=/mnt/ --exclude=/.snapshots/* --exclude=/var/tmp/ --exclude=/var/log/ /real_root/"$fsroot" $new_root

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

				if [ "$fs_type" = "ext4" ]; then
				echo "Mounting $fs_type..."
				#	umount $new_root
				#	mount -o noatime,commit=60 "$root_part" $new_root
				fi
                echo -e "Running default option..."
        #mount -o rw,noatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro --uuid $ESP_UUID $new_root/efi

        fi


}' > $mnt/usr/lib/initcpio/hooks/liveroot
	
	cat $mnt/usr/lib/initcpio/hooks/liveroot

	echo '#!/bin/sh

build() {
	add_binary rsync
	add_binary bash
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


	if [ "$fstype" = "btrfs" ]; then
		[ "$(cat $mnt/usr/lib/initcpio/install/liveroot | grep 'add_binary btrfs')" ] || sed -i 's/build() {/& \n        add_binary btrfs/g' $mnt/usr/lib/initcpio/install/liveroot
	fi


	echo 'MODULES=(lz4)
BINARIES=()
FILES=()
#HOOKS=(base udev keyboard autodetect kms modconf sd-vconsole block filesystems liveroot resume)
#HOOKS=(base udev keyboard autodetect kms modconf block filesystems liveroot resume)
HOOKS=(autodetect base keyboard block udev filesystems fsck liveroot resume)
COMPRESSION="lz4"
#COMPRESSION_OPTIONS=()
MODULES_DECOMPRESS="yes"' > $mnt/etc/mkinitcpio.conf

	echo 'ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"
#ALL_microcode=(/boot/*-ucode.img)

PRESETS=("default")

#default_config="/etc/mkinitcpio.conf"
default_image="/boot/initramfs-linux.img"' > $mnt/etc/mkinitcpio.d/linux.preset

	arch-chroot $mnt mkinitcpio -P 

	# So systemd won't remount as 'rw'
	#systemctl --root=$mnt mask systemd-remount-fs.service

	# Don't remount /efi either
	#systemctl --root=$mnt mask efi.mount

}



reset_keys () {

	#rm -rf /etc/pacman.d/gnupg
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

	echo -e "\nDowloading script from Github..."

	curl -sL https://raw.githubusercontent.com/bathtime/arch/main/arch.sh > $arch_path/$arch_file
	chmod +x $arch_path/$arch_file

}



clone () {

	check_on_root
	mount_disk


	echo -e "\n$1 $3 -> $4. Please be patient...\n"

	rsync $2 --exclude=/efi --exclude=/etc/fstab --exclude=/boot/refind_linux.conf --exclude=/root.squashfs --exclude=/home/$user/.cache/ --exclude /home/$user/.local/share/Trash/ --exclude=/dev/ --exclude=/proc/ --exclude=/sys/ --exclude=/tmp/ --exclude=/run/ --exclude=$mnt/ --exclude=/.snapshots/* --exclude=/var/tmp/ --exclude=/var/log/ --exclude=/var/lib/systemd/random-seed --exclude=/root/.cache/* --exclude=$mnt/ $3 $4

	echo -e "\nNOTE: You may need to update fstab!\n"
}



extract_archive () {

	check_on_root
	mount_disk

	unsquashfs -d $mnt -f /root.squashfs

}



create_archive () {


	#pacstrap_install squashfs-tools


	echo "Creating archive file..."

	cd / 
	rm -rf /root.squashfs

	time mksquashfs / root.squashfs -mem-percent 50 -no-recovery -noappend -e /boot/ -e /efi/ -e root.squashfs -e /dev/ -e /proc/ -e /sys -e /tmp -e /run -e /mnt -e /.snapshots/ -e /var/tmp/ -e /var/log/ -e /etc/pacman.d/gnupg/ -e /home/$user/.local/share/Trash/ -comp lz4  

	ls -lah root.squashfs

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

	echo "Copying $arch_path/$arch_file to $mnt$arch_path/..."

	mkdir -p $mnt$arch_path
	cp $arch_path/$arch_file $mnt$arch_path

	if [ "$root_only" -eq 0 ] && [ $(grep "^$user" $mnt/etc/passwd) ]; then
		arch-chroot $mnt chown $user:$user $arch_path/$arch_file
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

		[ "$copy_on_host" -eq 1 ] && pacman --noconfirm -S ${packages[@]}

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

		if [ "$copy_on_host" -eq 1 ] && [ ! "$(pacman -Q $package 2>/dev/null)" ]; then
			pacman --noconfirm -S ${packages[@]}
		fi

		if [ "$offline" -eq 1 ]; then
			pacstrap -C /etc/pacman-offline.conf -c -K $mnt ${packages[@]}
		else
			pacstrap -c -K $mnt ${packages[@]}
		fi

	fi
}

custom_install () {

	check_on_root
   mount_disk

	echo -e "Which package(s) would you like to install?\n"
	read packages

	if [ "$packages" ]; then
		pacstrap_install $packages
	else
		echo "No packages will be installed."
	fi


	copy_pkgs

}



create_snapshot () {

	btrfs subvolume list -t /

	echo -e "\nWhat would you like to name the snapshot?\n"
	read snapshot 

	if [ "$snapshot" ]; then
		btrfs subvolume snapshot / /.snapshots/"$snapshot"
	else
		echo "No name give. Exiting."
	fi

}



restore_snapshot () {

	echo "TODO!"


}



copy_pkgs () {

	check_on_root
	mount_disk

	# Check which packages are installed on chroot system
	packages="$(pacman --sysroot $mnt -Q | sed 's/ /-/g; s/$/-/g')"

	# Copy only packages from host system that are installed on chroot system
	for package in ${packages}; do

		#if [ "$(ls /var/cache/pacman/pkg/ | grep $package-*[0-9].*.pkg.tar.zst)" ]; then
		if [ "$(ls /var/cache/pacman/pkg/ | grep $package*)" ]; then

			echo -n "Copying $package... "

			# Only copy if the package is newer or nonexistant
			cp -u /var/cache/pacman/pkg/$package* $mnt/var/cache/pacman/pkg/ && echo "[done]"
		fi

	done

	echo -e "\n.zst packages: $(ls $mnt/var/cache/pacman/pkg/*.zst | wc -l)\n"
	echo -e "Total packages: $(ls $mnt/var/cache/pacman/pkg/* | wc -l)\n"

	#echo -e "\nUpdating package database. Please be patient...\n"

	#pacman-db-upgrade

	#repo-add -q -n /var/cache/pacman/pkg/./custom.db.tar.gz /var/cache/pacman/pkg/*.zst
	#repo-add -q -n $mnt/var/cache/pacman/pkg/./custom.db.tar.gz $mnt/var/cache/pacman/pkg/*.zst

	#pacman -U /mnt/var/cache/pacman/pkg/*.pkg.tar.zst
	#pacman -U /var/cache/pacman/pkg/*.pkg.tar.zst

}



check_online () {

	curl -Is  http://www.google.com &>/dev/null && online=1 || online=0

	if [ $online -eq 0 ]; then
		echo -e "\nNo internet connection found. Offline mode enabled."
		offline=1 
	fi

}



auto_install_root () {

	root_only=1

	create_partitions
	install_base
	setup_fstab

	# TODO make grub work with btrfs
	#if [ "$fstype" = "xfs" ] ; then
		install_GRUB
	#else
#		install_REFIND
#	fi

	general_setup
	setup_iwd
	install_tweaks
	install_liveroot
	copy_script
	copy_pkgs

}



auto_install_user () {

	root_only=0

	auto_install_root
	setup_user
	#install_tweaks
	copy_pkgs

}



auto_install_weston () {

	auto_install_user

	pacstrap_install wireplumber pipewire pipewire-pulse weston firefox foliate brightnessctl
	copy_pkgs
	
	sed -i 's/^:/  exec weston --shell=desktop/g' $mnt/home/$user/.bash_profile

	backup_config
	install_config

}



auto_install_kde () {

	auto_install_user
 
	pacstrap_install plasma-desktop plasma-pa kscreen dolphin konsole firefox chromium gimp gwenview okular obs-studio ffmpegthumbs bleachbit ncdu
	
	copy_pkgs

	# Auto-launch
	sed -i 's/^:/   startplasma-wayland/g' $mnt/home/$user/.bash_profile

   if [ "$fstype" = "btrfs" ]; then
		install_timeshift
	fi

	#backup_config
	install_config	
	sync_disk

}


auto_install_gnome () {

	auto_install_user

	pacstrap_install gnome-shell nautilus gnome-terminal xdg-user-dirs firefox
	copy_pkgs

	# Customize system

	sed -i 's/^:/   MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland XDG_SESSION_TYPE=wayland gnome-shell --session=wayland/g' $mnt/home/$user/.bash_profile

	backup_config
	install_config
}


clean_system () {

	#echo "Cleaning unused locales..."
	#ls /usr/share/locales/ | grep -xv "en_US" | xargs rm -r


	echo "Cleaning ~/.cache..."
	rm -rf /home/user/.cache/*
	
	echo "Cleaning mozilla..."

	cd /home/$user/.mozilla/firefox
	rm -rf 'Crash Reports' 'Pending Pings'

	profile=$(ls /home/user/.mozilla/firefox/ | grep .*.default-release)
	cd $profile

	rm -rf crashes minidumps datareporting sessionstore-backups saved-telemetry-pings storage browser-extension-data security_state gmp-gmpopenh264 synced-tabs.db-wal places.sqlite favicons.sqlite cert9.db places.sqlite-wal storage-sync-v2.sqlite-wal webappsstore.sqlite gmp-widevinecdm


	echo "Cleaning chromium..."

	cd /home/$user/.config/chromium

	#rm -rf Safe\ Browsing component_crx_cache WidevineCdm IndexedDB GrShaderCache OnDeviceHeadSuggestModel hyphen-data ZxcvbnData ShaderCache Default/{Service\ Worker/,IndexedDB,History,GPUCache,Sessions,DawnCache,Extension\ State,Web\ Data,Visited\ Links}
	#rm -rf Safe\ Browsing component_crx_cache WidevineCdm GrShaderCache OnDeviceHeadSuggestModel hyphen-data ZxcvbnData ShaderCache Default/{Service\ Worker/,History,GPUCache,Sessions,DawnCache,Extension\ State,Web\ Data,Visited\ Links}

}



backup_config () {

	clean_system

	cd /home/$user
	rm -rf setup.tar

	sudo -u $user tar -pcf setup.tar $CONFIG_FILES
	chown $user:$user $mnt/home/$user/setup.tar

	#sudo -u $user gpg --yes -c setup.tar
	
	#ls -lah setup.tar setup.tar.gpg
	ls -lah setup.tar

}



restore_config () {

	cd /home/$user

	echo "Extracting setup file..."
	sudo -u $user tar xvf setup.tar

}



install_config () {

	check_on_root
	mount_disk

	#read -p "Press any key when ready to enter password."
	#echo "Decrypting setup file..."
	#gpg --yes --output /home/$user/setup.tar --decrypt /home/$user/setup.tar.gpg


	#cp /home/$user/setup.tar{,.gpg} $mnt/home/$user/
	cp /home/$user/setup.tar $mnt/home/$user/

	echo "Extracting setup file..."
	arch-chroot -u $user $mnt tar xvf /home/$user/setup.tar --directory /home/$user

}


last_modified () {

	cd /home/$user
	find . -cmin -1 -printf '%t %p\n' | sort -k 1 -n | cut -d' ' -f2-

}



edit_arch () {

	if [ "$(ls $arch_path | grep $arch_file)" ]; then
		vim $arch_path/$arch_file && exit
	fi

}



wipe_disk () {

	check_on_root
	unmount_disk


	echo -e "\nDisk: $disk_info\n\nType 'yes' to wipe using $1 method.\n"
	read choiceWipe
	
	if [[ $choiceWipe = yes ]]; then

		echo -e "\nWiping $disk using $1 method. Please be patient...\n"

		error_check 0
		time dd if=/dev/$1 of=$disk bs=1M status=progress
		error_check 1

	else
		echo -e "\nNot wiping.\n"
	fi

}


wipe_freespace () {


	echo -e "\nWiping freespace on $disk using zero method. Please be patient...\n"
	echo -e "Run 'watch -n 1 -x df / --sync' in another terminal to see progress.\n"

	error_check 0

	cd /

	file=$(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 32).tmp
	(dd if=/dev/zero of=$file bs=4M status=progress; dd if=/dev/zero of=$file.small bs=256 status=progress) &>/dev/null


	sync ; sleep 60 ; sync
	rm $file $file.small

	error_check 1

}



disk_info () {

	echo -ne "\nDisk: $(lsblk --output=PATH,SIZE,MODEL,TRAN -dn $disk) "

	[[ $(lsblk -no MOUNTPOINT $disk$rootPart) ]] && echo "(mounted)" || echo "(unmounted)"

}



sync_disk () {

	echo
	sync &

	dirty=$(cat /proc/meminfo | awk '/Dirty:/ { print $2 }')
	initial_dirty=$dirty
	stall_count=0

	while [[ $dirty -gt $dirty_threshold ]]; do

		dirty=$(cat /proc/meminfo | awk '/Dirty:/ { print $2 }')
		[ $dirty -ne 0 ] && perc=$(( 100 - (dirty * 100 / initial_dirty) )) || perc=100 

		printf '\rSyncing: %i kB... (%i%%)   ' $dirty $perc

		if [[ $dirty -ge $last_dirty ]]; then
			stall_count=$(( stall_count + 1 ))
		else
			stall_count=0
		fi

		last_dirty=$dirty
		
		if [ $stall_count -gt 10 ]; then
			sync &
			stall_count=0
			echo "Resyncing..."
		fi

		sleep .1

	done

	echo
	sleep .5

}


CONFIG_FILES=".config/baloofilerc
.config/chromium
.config/dolphinrc
.config/epy/*
.config/fontconfig/fonts.conf
.config/gtkrc
.config/gtkrc-2.0
.config/gwenviewrc
.config/htop
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
.config/kwinoutputconfig.json
.config/kwinrc
.config/kwinrulesrc
.config/okularrc
.config/plasma-org.kde.plasma.desktop-appletsrc
.config/plasmashellrc
.config/powerdevilrc
.config/powermanagementprofilesrc
.config/systemsettingsrc
.config/Trolltech.conf
.config/weston.ini
.config/vlc/*
.local/bin/*
.local/lib/*
.local/share/applications/*
.local/share/color-schemes/*
.local/share/dolphin/*
.local/share/fonts/*
.local/share/icons/*
.local/share/konsole/*.profile
.local/share/kxmlgui5/*
.local/share/plasma/plasmoids/*
.local/share/user-places.xbel
.viminfo
.mozilla/*"

if [ "$1" ]; then
	disk="$1"
else
	choose_disk
fi


check_viable_disk
disk_info

check_online


# Make font big and readable
if [ -f /usr/share/kbd/consolefonts/ter-132b.psf.gz ]; then
	setfont ter-132b
fi


choices=("1. Quit
2. Edit $arch_file
3. Chroot
4. Change disk ($disk)
5. Partition disk
6. Install base
7. Hypervisor setup
8. Setup fstab
9. Install boot manager
10. General setup
11. Setup user
12. Setup network
13. Install aur
14. Install tweaks
15. Install mksh
16. Install liveroot
17. Create snapshot /
18. Restore snapshot /
19. Mount $mnt
20. Unmount $mnt
21. Create squashfs image
22. Connect wireless
23. Download script
24. Install host packages
25. Reset pacman keys
26. Copy packages
27. Auto-install
28. Copy script
29. Choose initramfs
30. Custom install
31. Setup files
32. Unsquash to target
33. Part + Clone / -> $disk
34. Clone / -> $disk
35. Clone $disk -> /
36. Copy / -> $disk
37. Copy $disk -> /
38. Copy /home -> $disk$rootPart/
39. Copy $disk$rootPart/home -> /
40. Update / <-> $disk
41. Wipe (zero)
42. Wipe (urandom)
43. Wipe freespace")


while :; do

echo
echo "${choices[@]}" | column   

echo -ne "\nEnter an option: "

read choice

echo

	case $choice in
		Quit|quit|q|exit|1)	break; exit ;;
		arch|2)					edit_arch ;;
		Chroot|chroot|3)		do_chroot ;;
		disk|4)					choose_disk ;;
		partition|5)			create_partitions ;;
		base|6)					install_base ;;
		hypervisor|7)			hypervisor_setup ;;
		fstab|8)					setup_fstab ;;
		boot|9)					install_bootloader ;;
		setup|10)				general_setup ;;
		user|11)					setup_user ;;
      network|12)				install_network ;;
		aur|13)					install_aur ;;
		tweaks|14)				install_tweaks ;;
      mksh|15)					install_mksh ;;
		liveroot|16)			install_liveroot ;;
		create_snapshot|17)	create_snapshot ;;
		restore_snapshot|18)	restore_snapshot ;;
      mount|19)				mount_disk  ;;
      unmount|20)				unmount_disk  ;;
		squashfs|21)			create_archive ;;
		connect|iwd|22)		connect_wireless ;;
		script|23)				download_script; exit ;;
		host|24)			 		install_host_packages ;;
		reset|keys|25)			reset_keys ;;
		pkgs|26)					copy_pkgs ;;
		root|27)					config_os=("1. Quit
2. Root
3. User
4. Weston
5. KDE
6. Gnome")
										echo
										echo "${config_os[@]}" | column
										echo  

										read -p "Which option? " config_os

        								case $config_os in
                						quit|1)		;;
                						root|2)		auto_install_root; copy_pkgs ;;
                						user|3)		auto_install_user; copy_pkgs;;
                						weston|4)	time auto_install_weston ;;
                						kde|5)		time auto_install_kde ;;
                						gnome|6)		time auto_install_gnome ;;
                						'')			;;
	              						*)				echo -e "\nInvalid option ($config_os)!\n" ;;
										esac ;;

		copy_script|28)		copy_script ;;
		initramfs|29)			choose_initramfs ;;
		custom|30)				custom_install ;;
		setup|31)			config_choices=("1. Quit
2. Backup config
3. Restore config
4. Install config
5. Cleanup system
6. Last modified")			config_choice=0

									while [ ! "$config_choice" = "1" ]; do

										echo
										echo "${config_choices[@]}" | column
										echo  

										read -p "Which option? " config_choice

        								case $config_choice in
                						quit|1)		echo "Quitting!"; break; ;;
                						backup|2)	backup_config ;;
                						restore|3)	restore_config ;;
                						install|4)	install_config ;;
                						clean|5)		clean_system ;;
                						last|6)		last_modified ;;
                						'')			last_modified ;;
                						*)				echo -e "\nInvalid option ($config_choice)!\n" ;;
										esac

									done ;;
	
		unsquash|32)			extract_archive ;;
		clone|33)				create_partitions
									clone Cloning "-av --del" / $mnt/
									setup_fstab
									install_REFIND ;;
		clone|34)				clone Cloning "-av --del" / $mnt/ ;; 
		clone|35)				clone Cloning "-av --del" $mnt/ / ;;
		copy|36)					clone Copying -av / $mnt/ ;;
		copy|37)					clone Copying -av $mnt/ / ;;
		copy|38)					clone Copying -av /home $mnt/ ;;
		copy|39)					clone Copying -av $mnt/home / ;;
		update|40)				clone Updating -auv / $mnt/ ; clone Updating -auv $mnt/ / ;;
		wipe|41)					wipe_disk zero ;;
		wipe|42)					wipe_disk urandom ;;
		wipe-free|43)			wipe_freespace ;;
		'')						disk_info ;;
		*)							echo -e "\nInvalid option ($choice)!\n"; ;;
	esac

	sync_disk

done

unmount_disk


