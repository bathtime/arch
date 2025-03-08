#!/bin/bash


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

		if [[ "$error_bypass" = '1' ]]; then
			choice=c
			echo -e "\nSkipping error.\n"
		else
			read -p "Choice: " -n 2 choice
		fi

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

	case $1 in
		0)		set +e; echo "No error detection!" ;;
		1)		set -Eeo pipefail ;;
		2)		set -Eueo pipefail ;;
		3)		echo "All commands issured will be printed."; set -Eeox pipefail ;;
	esac

}

error_check 1
error_bypass=0


# Make font big and readable and make sure the hook for the font is turnted on
if [ -f /usr/share/kbd/consolefonts/ter-132b.psf.gz ] && [[ ! $(cat /etc/mkinitcpio.conf | grep -e '^HOOKS|consolefont') = '' ]]; then
	setfont ter-132b
fi


arch_file=$(basename "$0")
arch_path=$(dirname "$0")

mnt=/mnt
bootOwnPartition='true'		# make separate boot partition (true/false)?

if [[ $bootOwnPartition = 'true' ]]; then
	espPartNum=1
	bootPartNum=2
	swapPartNum=3
	rootPartNum=4
else
	bootPartNum=0
	espPartNum=1
	swapPartNum=2
	rootPartNum=3
fi

espPart=$espPartNum
bootPart=$bootPartNum
swapPart=$swapPartNum
rootPart=$rootPartNum
startSwap='8192Mib'			# 2048,4096,8192,(8192 + 1024 = 9216) 
fsPercent='50'					# What percentage of space should the root drive take?
fstype='bcachefs'				# btrfs,ext4,bcachefs,f2fs,xfs,jfs,nilfs2
subvols=()			# used for btrfs and bcachefs
subvolPrefix='/'				# eg., '/' or '/@'
snapshot_dir="/snapshots"
linkedToTmp='true'			# Link /var/log and /var/tmp to /tmp?
backup_install='true'		# say 'true' to do snapshots/rysncs during install
timeshift_on='true'			# Works only under btrfs
initramfs='booster'			# mkinitcpio, dracut, booster
encrypt=false
efi_path=/efi


kernel_ops="nmi_watchdog=0 nowatchdog modprobe.blacklist=iTCO_wdt mitigations=off loglevel=3 rd.udev.log_level=3 zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=20 scsi_mod.use_blk_mq=1"


user=user
password='123456'
autologin=true
aur_app=none
aur_path=/home/$user/aur

base_install="base linux linux-firmware vim parted gptfdisk arch-install-scripts pacman-contrib tar man-db dosfstools"

user_install="sudo git base-devel"

cage_install="cage firefox"

weston_install="brightnessctl wireplumber pipewire pipewire-pulse weston firefox"

gnome_install="gnome-shell polkit nautilus gnome-console xdg-user-dirs firefox dconf-editor gnome-browser-connector gnome-shell-extensions gnome-control-center gnome-weather"

phosh_install="phosh phoc phosh-mobile-settings squeekboard firefox"

kde_install="plasma-desktop plasma-pa maliit-keyboard plasma-nm kscreen iio-sensor-proxy dolphin konsole ffmpegthumbs bleachbit ncdu"

ucode=intel-ucode
hostname=Arch
timezone=Canada/Eastern

offline=0
reinstall=0
copy_on_host='1'	# Set to '0' when installing from an arch iso in ram

wlan="wlan0"
wifi_ssid=""
wifi_pass=""

dirty_threshold=0



check_pkg () {

	for package in "$@"; do

   	if [ ! "$(pacman -Q $package)" ]; then
      	echo -e "\nInstalling program required to run command: $package...\n"
      	pacman --noconfirm -S $package
   	fi

	done

}



check_viable_disk () {

	if [[ "$disk" == "" ]]; then
		echo -e "\nMissing disk parameter. Exiting.\n"
  		exit
	fi

	if [[ ! "$(lsblk --output=PATH -d -n | grep $disk)" ]]; then
		echo -e "\nNo such disk found ($disk). Exiting.\n"
		sleep 2
		exit
	fi

}



check_on_root () {
  
	if [[ $(mount | grep -G "$disk.*on / type") ]]; then 
		echo -e "\nDevice mounted on root. Will not run. Exiting.\n"
		sleep 2
		exit
	fi

}



unmount_disk () {

	sync_disk

	[ "$mnt" = '' ] && return


	if [[ $(mount | grep -E $disk$espPart | grep -E "on $mnt$efi_path") ]]; then
		echo "Unmounting $mnt$efi_path..."
		umount -n -R $mnt$efi_path
		sleep .1
	fi

	if [[ $(mount | grep -E $disk$bootPart | grep -E "on $mnt/boot") ]] && [[ $bootOwnPartition = true ]]; then
		echo "Unmounting $mnt/boot..."
		umount -n -R $mnt/boot
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

}



choose_disk () {

	search_disks=1
	host="$(mount | awk '/ on \/ / { print $1}' | sed 's/p*[0-9]$//g')"

	while [ $search_disks -eq 1 ]; do
		
		mnt=''

		echo -e "\nDrives found (current mount: /):\n"
		
		rootfs=$(mount | grep ' / ' | sed 's/(.*//; s/\/dev.* type //; s/ //')

		lsblk --output=PATH,SIZE,MODEL,TRAN -d | grep -P "/dev/sd|nvme|vd" | sed "s#$host.*#&  $rootfs#g" | sed "s#$host.*#& (host)#g"

		choices='quit sync edit $ # '$(lsblk -dpnoNAME|grep -P "/dev/sd|nvme|vd")' / script logout reboot suspend hibernate poweroff stats benchmark'
		

		echo -e "\nWhich drive?\n"

	select disk in $choices
		do
			case $disk in
				quit)			sync_disk; exit ;;
				edit)			vim $arch_path/$arch_file; exit ;;
				$)				sudo -u $user bash ;;
				\#)			bash ;;
				sync)			sync_disk ;;
				script)		download_script ;;
				logout)		killall systemd ;;
				reboot)		reboot ;;
				suspend)		echo mem > /sys/power/state ;;
				hibernate)	echo disk > /sys/power/state ;;
				poweroff)	poweroff ;;
				benchmark)	benchmark ;;
				stats)	  	
								if [[ "$rootfs" = 'btrfs' ]]; then
									btrfs su list /
								fi

								echo; free -h; echo
								systemd-analyze | sed 's/in .*=/in/;s/graph.*//'
								echo $(systemd-analyze  blame | wc -l) systemd services
								;;
				/)				disk=$host; search_disks=0; break ;;
				*)    		if [[ $disk = '' ]]; then
						   		
									echo -e "\nInvalid option!\n"
								
								else
									
									if [[ "$(mount | awk '/ on \/ / { print $1}' | sed 's/p*[0-9]$//g')" = $disk ]]; then
										mnt=''
									else
										mnt='/mnt'
									fi

									search_disks=0
									break
								
								fi
								;;
				'')   		echo -e "\nInvalid option!\n" ;;
			esac

		done

	if [ "$(echo $disk | grep nvme)" ]; then
		bootPart="p$bootPartNum"
		espPart="p$espPartNum"
		swapPart="p$swapPartNum"
		rootPart="p$rootPartNum"
	else
		bootPart="$bootPartNum"
		espPart="$espPartNum"
     	swapPart="$swapPartNum"
     	rootPart="$rootPartNum"
	fi

	echo -e "\nDisk chosen: $disk (mounted on $mnt/)"
	
	done
}



delete_partitions () {

	check_on_root
	unmount_disk

	echo -e "\nWiping disk...\n"

	wipefs -af $disk

	check_pkg gptfdisk

	sgdisk -Zo $disk

}


fs_packages () {

	case $fstype in
		btrfs)		pacstrap_install btrfs-progs grub-btrfs ;;
		bcachefs)	pacstrap_install bcachefs-tools ;;
		xfs)			pacstrap_install xfsprogs ;;
		f2fs)			pacstrap_install f2fs-tools ;;
		jfs)			pacstrap_install jfsutils ;;
		nilfs2)		pacstrap_install nilfs-utils ;;
	esac
}


create_partitions () {

	check_on_root

	delete_partitions
	
	systemctl daemon-reload

	check_pkg parted dosfstools

	if [ $bootOwnPartition = true ]; then

		parted -s $disk mklabel gpt \
			mkpart ESP fat32 1Mib 512Mib \
			mkpart BOOT ext2 512Mib 1024Mib \
			mkpart SWAP linux-swap 1024Mib $startSwap \
			set $espPartNum esp on \
			set $swapPartNum swap on
				
			mkfs.ext2 -F -L BOOT $disk$bootPart 
		
	else

		parted -s $disk mklabel gpt \
			mkpart ESP fat32 1Mib 512Mib \
			mkpart SWAP linux-swap 1024Mib $startSwap \
			set $espPartNum esp on \
			set $swapPartNum swap on
		
	fi

	if [ $fstype = bcachefs ]; then
		# Parted doesn't recognise bcachefs filesystem
		parted -s $disk mkpart ROOT ext4 $startSwap $fsPercent%
	else
		parted -s $disk mkpart ROOT $fstype $startSwap $fsPercent%
	fi

	parted -s $disk print

	# Won't work without a small delay
	sync_disk
	#sleep 1

	mkfs.fat -F 32 -n EFI $disk$espPart 
	mkswap -L SWAP $disk$swapPart

	# Install packages required for filesystem
	fs_packages

	case $fstype in

		btrfs)		mkfs.btrfs -f -L ROOT $disk$rootPart ;;
		ext4)			
						mkfs.ext4 -F -b 4096 -q -t ext4 -L ROOT $disk$rootPart 
						echo "Using tune2fs to create fast commit journal area. Please be patient..." 
						tune2fs -O fast_commit $disk$rootPart
						tune2fs -l $disk$rootPart | grep features ;;
		xfs)			mkfs.xfs -f -L ROOT $disk$rootPart ;;
		jfs)			mkfs.jfs -f -L ROOT $disk$rootPart ;;
		f2fs)			mkfs.f2fs -f -l ROOT $disk$rootPart ;;
		nilfs2)		mkfs.nilfs2 -f -L ROOT $disk$rootPart ;;
		bcachefs)		
						if [[ $encrypt = true ]]; then
							bcachefs format -f -L ROOT --encrypted $disk$rootPart
							bcachefs unlock -k session $disk$rootPart
						else
							bcachefs format --block_size=4096 -f -L ROOT $disk$rootPart
						fi
						;;
	esac

	parted -s $disk print

	sync_disk
	echo -e "\nPausing for 1 second...\n"
	sleep 1
	
	cd /

	echo -e "\nMounting $mnt..."

	mount -t $fstype --mkdir $disk$rootPart $mnt

	if [ "$fstype" = "btrfs" ]; then

		if [[ ! $subvolPrefix = '/' ]] && [[ ! $subvolPrefix = '' ]]; then
			echo btrfs su cr --parents "$mnt$subvolPrefix"
			btrfs su cr --parents "$mnt$subvolPrefix"
		fi

		for subvol in "${subvols[@]}"; do
			echo btrfs su cr --parents "$mnt$subvolPrefix$subvol"
			btrfs su cr --parents "$mnt$subvolPrefix$subvol"
		done

	fi

	if [ "$fstype" = "bcachefs" ]; then
	
		for subvol in "${subvols[@]}"; do

			echo -e "Creating subvolume: $mnt$subvolPrefix$subvol..."
			mkdir -p "$(dirname $mnt$subvolPrefix$subvol)"
		
			bcachefs subvolume create "$mnt$subvolPrefix$subvol"
		
		done

	fi

	unmount_disk
	mount_disk

	mkdir -p $mnt/{dev,etc,proc,root,run,sys,tmp,var/cache/pacman/pkg,/var/tmp,/var/log}
	
	if [ "$fstype" = "bcachefs" ]; then
		mkdir -p $mnt$snapshot_dir
	fi


	chmod -R 750 $mnt/root
	mkdir -p $mnt/root/.gnupg
	chmod -R 700 $mnt/root/.gnupg
	chmod -R 1777 $mnt/var/tmp

}


mount_disk () {

	# No need to mount if we're on the main machine
	[ "$mnt" = "" ] && return

	check_on_root

	if [[ ! $(mount | grep -E $disk$rootPart | grep -E "on $mnt") ]]; then

		if [ "$fstype" = "btrfs" ]; then

			echo -e "\nMounting...\n"

			mountopts="noatime,discard=async"
			
			if [[ ! $subvolPrefix = '/' ]] && [[ ! $subvolPrefix = '' ]]; then

				subvol=''
				echo mount --mkdir -o "$mountopts",subvol="$subvolPrefix$subvol" $disk$rootPart $mnt/$subvol
				mount --mkdir -o "$mountopts",subvol="$subvolPrefix$subvol" $disk$rootPart $mnt/$subvol

			else
			
				mount -t $fstype --mkdir $disk$rootPart $mnt
			
			fi

			for subvol in "${subvols[@]}"; do
				
				echo mount --mkdir -o "$mountopts",subvol="$subvolPrefix$subvol" $disk$rootPart $mnt/$subvol
				mount --mkdir -o "$mountopts",subvol="$subvolPrefix$subvol" $disk$rootPart $mnt/$subvol

			done
			
		elif [[ $fstype = bcachefs ]]; then
	
			mount -t $fstype --mkdir $disk$rootPart $mnt

			for subvol in "${subvols[@]}"; do
			
				echo mount --bind $mnt$subvolPrefix$subvol $mnt$subvolPrefix$subvol
				mount --bind $mnt$subvolPrefix$subvol $mnt$subvolPrefix$subvol
			
			done

			if [[ $encrypt = true ]] && [[ $fstype = bcachefs ]]; then
				bcachefs unlock -k session $disk$rootPart
			fi

		else

			mount -t $fstype --mkdir $disk$rootPart $mnt	

		fi

	fi
	
	if [[ ! $(mount | grep -E $disk$bootPart | grep -E "on $mnt/boot") ]] && [[ $bootOwnPartition = true ]]; then
		mount --mkdir $disk$bootPart $mnt/boot
	fi

	if [[ ! $(mount | grep -E $disk$espPart | grep -E "on $mnt$efi_path") ]]; then
		mount --mkdir $disk$espPart $mnt$efi_path
	fi

}



install_base () {

	mount_disk

	echo '[options]
HoldPkg     = pacman glibc
Architecture = auto

CheckSpace
ParallelDownloads = 5
Color

[custom]
SigLevel = Optional TrustAll
Server = file:///var/cache/pacman/pkg/
' > /etc/pacman-offline.conf
	
	if [ ! $mnt = '' ]; then

		cp /etc/pacman-offline.conf $mnt/etc/pacman-offline.conf


		if [ "$offline" -eq 1 ]; then
			echo "Copying database files..."
			mkdir -p $mnt/var/lib/pacman/sync
			cp -r /var/lib/pacman/sync/*.db $mnt/var/lib/pacman/sync/
		fi

	fi

	reset_keys

	check_pkg arch-install-scripts

	#check_pkg reflector
	#echo -e "\nRunning reflector...\n"
	#reflector > /etc/pacman.d/mirrorlist

	[ "$(cat /etc/pacman.d/mirrorlist)" = "" ] && update_mirrorlist


	mkdir -p $mnt/etc/pacman.d
	[ ! $mnt = '' ] && cp /etc/pacman.d/mirrorlist $mnt/etc/pacman.d/mirrorlist

	packages="$base_install"

	[ "$fstype" = "btrfs" ] && packages="$packages btrfs-progs grub-btrfs rsync"
	[ "$fstype" = "xfs" ] && packages="$packages xfsprogs"
	[ "$fstype" = "jfs" ] && packages="$packages jfsutils"
	[ "$fstype" = "f2fs" ] && packages="$packages f2fs-tools"
	[ "$fstype" = "nilfs2" ] && packages="$packages nilfs-utils"
	[ "$fstype" = "bcachefs" ] && packages="$packages bcachefs-tools rsync"

	pacstrap_install $packages

	cp $mnt/etc/pacman.conf $mnt/etc/pacman.conf.pacnew

	sed -i 's/#Color/Color/' $mnt/etc/pacman.conf
	sed -i 's/CheckSpace/#CheckSpace/' $mnt/etc/pacman.conf
	sed -i 's/#ParallelDownloads.*$/ParallelDownloads = 5/' $mnt/etc/pacman.conf
	#sed -i 's/SigLevel    = .*$/SigLevel    = TrustAll/' $mnt/etc/pacman.conf

}


auto_login () {

	login_user=$1

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

	choices=(exit auto kvm vmware oracle microsoft)

   select choice in "${choices[@]}"; do
		case $choice in
			auto)			hypervisor=$(systemd-detect-virt) 
							echo "Detected: $hypervisor" ;;
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
			exit)			break ;;
			*)    		echo -e "\nInvalid option!\n" ;;
			'')   		echo -e "\nInvalid option!\n" ;;
		esac
	done

}



setup_fstab () {

	mount_disk

	echo -e "\nCreating new /etc/fstab file...\n"

	genfstab -U $mnt/ > $mnt/etc/fstab
	grep $disk /proc/mounts > $mnt/etc/fstab.bak


	###  Tweak the resulting /etc/fstab generated  ###

	SWAP_UUID=$(blkid -s UUID -o value $disk$swapPart)

	# Changing compression
	sed -i 's/zstd:3/zstd:1/' $mnt/etc/fstab

	# Bad idea to use subids when rolling back 
	#sed -i 's/subvolid=.*,//g' $mnt/etc/fstab

	# genfstab will generate a swap drive. we're using a swap file instead
	sed -i '/LABEL=SWAP/d; /none.*swap.*defaults/d' $mnt/etc/fstab

	sed -i 's/relatime/noatime/g' $mnt/etc/fstab
	

	sed -i '/portal/d' $mnt/etc/fstab

	sed -i 's/\/.*ext4.*0 1/\/      ext4    rw,noatime,commit=60      0 1/' $mnt/etc/fstab

	# Make /efi read-only
	#sed -i 's/\/efi.*vfat.*rw/\/efi     vfat     ro/' $mnt/etc/fstab

	systemctl daemon-reload

	cat $mnt/etc/fstab

}



choose_initramfs () {

	mount_disk

	if [ "$1" ]; then
		choice=$1
	else

		echo -e "\nWhich initramfs would you like to install?\n
1. quit 2. mkinitcpio 3. dracut 4. booster\n"

		read choice
	fi

	case $choice in
		quit|1)			;;
		mkinitcpio|2)	pacstrap_install mkinitcpio ;;
		dracut|3)		pacstrap_install dracut 

							echo 'hostonly="yes"
compress="lz4"
add_drivers+=" "
omit_dracutmodules+=" "' > $mnt/etc/dracut.conf.d/myflags.conf

							if [[ $mnt = '' ]]; then
								dracut -f $mnt/boot/initramfs-linux.img
								#dracut --regenerate-all $mnt/boot/initramfs-linux.img
								dracut -f $mnt/boot/initramfs-linux-fallback.img
								grub-mkconfig -o $mnt/boot/grub/grub.cfg
							else
								arch-chroot $mnt dracut -f /boot/initramfs-linux.img
								#arch-chroot $mnt dracut --regenerate-all /boot/initramfs-linux.img
								arch-chroot $mnt dracut -f /boot/initramfs-linux-fallback.img
								arch-chroot $mnt grub-mkconfig -o /boot/grub/grub.cfg
							fi

							;;
		booster|4)		pacstrap_install booster 
							
							# manual build
							booster build /boot/booster-linux.img --force

							if [[ $mnt = '' ]]; then	
								grub-mkconfig -o $mnt/boot/grub/grub.cfg
							else
								arch-chroot $mnt grub-mkconfig -o /boot/grub/grub.cfg
							fi
							;;
		*)					echo -e "Invalid option!" ;;
	esac

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



install_grub () {

	mount_disk


	pacstrap_install grub os-prober efibootmgr inotify-tools lz4


	SWAP_UUID=$(blkid -s UUID -o value $disk$swapPart)
   echo "$SWAP_UUID"

	[[ $fstype = bcachefs ]] && extra_ops='rootfstype=bcachefs'
	
	# May cause grub-snapshots to not work correctly
	if [[ $fstype = btrfs ]] && [[ $subvolPrefix = '/@' ]]; then
		extra_ops='rootflags=subvol=@'
	fi

	grub-install --target=x86_64-efi --efi-directory=$mnt$efi_path --bootloader-id=GRUB --removable --boot-directory=$mnt/boot

	cat > $mnt/etc/default/grub << EOF2

GRUB_DISTRIBUTOR=""
GRUB_DEFAULT=saved
GRUB_SAVEDEFAULT=true
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="$kernel_ops $extra_ops resume=UUID=$SWAP_UUID"
GRUB_DISABLE_RECOVERY="true"
#GRUB_HIDDEN_TIMEOUT=1
GRUB_RECORDFAIL_TIMEOUT=1
GRUB_TIMEOUT=1
GRUB_DISABLE_OS_PROBER=true

# Update grub with:
# grub-mkconfig -o /boot/grub/grub.cfg

EOF2


	# Allows grub to run snapshots
	#if [ "$fstype" = "btrfs" ]; then
	#	systemctl --root=$mnt enable grub-btrfsd.service
	#	/etc/grub.d/41_snapshots-btrfs
	#fi

	# Remove grub os-prober message
	#sed -i 's/grub_warn/#grub_warn/g' $mnt/etc/grub.d/30_os-prober

	###  Offer readonly grub booting option  ###
	#cp $mnt/etc/grub.d/10_linux $mnt/etc/grub.d/10_linux-readonly
	#sed -i 's/\"\$title\"/\"\$title \(readonly\)\"/g' $mnt/etc/grub.d/10_linux-readonly
	#sed -i 's/ rw / ro /g' $mnt/etc/grub.d/10_linux-readonly

	#cp $mnt/etc/grub.d/10_linux $mnt/etc/grub.d/10_linux-nomodeset
	#sed -i 's/\"\$title\"/\"\$title \(nomodeset\)\"/g' $mnt/etc/grub.d/10_linux-nomodeset
	#sed -i 's/ rw / rw nomodeset /g' $mnt/etc/grub.d/10_linux-nomodeset


	if [[ $mnt = '' ]]; then
		grub-mkconfig -o $mnt/boot/grub/grub.cfg
	else
		arch-chroot $mnt grub-mkconfig -o /boot/grub/grub.cfg
	fi

	# btrfs cannot store saved default so will result in spare file error
	if [ "$fstype" = "btrfs" ] && [ "$bootOwnPartition" = "false" ]; then
		sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' $mnt/etc/default/grub	
		sed -i 's/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=false/' $mnt/etc/default/grub
	fi


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


	echo '# mkinitcpio preset file for the 'linux' package

#ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default' 'fallback')

#default_config="/etc/mkinitcpio.conf"
default_image="/boot/initramfs-linux.img"
#default_uki="/efi/EFI/Linux/arch-linux.efi"
#default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"

#fallback_config="/etc/mkinitcpio.conf"
fallback_image="/boot/initramfs-linux-fallback.img"
#fallback_uki="/efi/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
' > $mnt/etc/mkinitcpio.d/linux.preset

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

	mount_disk

	#	echo "$password" | passwd --stdin && echo "Root password created."
	echo "root:$password" | chpasswd --root=$mnt/ && echo "Root password created."

	echo -e 'en_US.UTF-8 UTF-8\nen_US ISO-8859-1' > $mnt/etc/locale.gen  
	echo 'LANG=en_US.UTF-8' > $mnt/etc/locale.conf
	echo 'Arch-Linux' > $mnt/etc/hostname
	echo 'KEYMAP=us' > $mnt/etc/vconsole.conf
	#arch-chroot $mnt ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
	ln -sf $mnt/usr/share/zoneinfo/$timezone $mnt/etc/localtime

	echo "127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname" > $mnt/etc/hosts

	echo '[[ $- != *i* ]] && return
alias ls="ls --color=auto"
alias grep="grep --color=auto"
alias vi="vim"
alias arch="sudo /usr/local/bin/arch.sh"
PS1="# "' > $mnt/root/.bashrc

	if [[ $mnt = '' ]]; then
		hwclock --systohc
		locale-gen
	else
		arch-chroot $mnt hwclock --systohc
		arch-chroot $mnt locale-gen
	fi

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

	mount_disk

	pacstrap_install sudo

	if [ "$(grep -c "^$user" $mnt/etc/passwd)" -eq 0 ]; then
		useradd --root=$mnt/ -m $user -G wheel -p "$password"
		echo "$user:$password" | chpasswd --root=$mnt/ && echo "User password created."
	fi
	
	if [ "$(grep -c "^$user" $mnt/etc/passwd)" -eq 0 ]; then
		echo -e "\nUser was not created. Exiting.\n"
		exit
	fi


	rm -rf $mnt/home/$user/.cache

	# TODO: find a way to create symbolic link from host
	if [[ $mnt = '' ]]; then
		ln -s $mnt/tmp $mnt/home/$user/.cache
		visudo -c
	else
		arch-chroot $mnt ln -s /tmp /home/$user/.cache
		arch-chroot $mnt visudo -c
	fi


	chown -R $user:$user $mnt/home/$user/.cache

  # arch-chroot $mnt /bin/bash -e << EOF
	#	rm -rf /home/$user/.cache
	#	ln -s /tmp /home/$user/.cache
	#	chown -R user:user /home/$user/.cache
#EOF

	mkdir -p -m 750 $mnt/etc/sudoers.d
	echo '%wheel ALL=(ALL:ALL) ALL' > $mnt/etc/sudoers.d/1-wheel
	echo "$user ALL = NOPASSWD: /usr/local/bin/arch.sh" > $mnt/etc/sudoers.d/10-arch
	chmod 0440 $mnt/etc/sudoers.d/{1-wheel,10-arch}
	
	
	# Autologin to tty1
	mkdir -p $mnt/etc/systemd/system/getty@tty1.service.d
	echo "[Service]
Type=simple
ExecStart=
ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin $user --noclear %I 38400 linux" > $mnt/etc/systemd/system/getty@tty1.service.d/autologin.conf

	#sudo -u $user mkdir -p $mnt/home/$user/.local/bin
	sudo -u $user mkdir -p $mnt/home/$user/{.local/bin,Documents,Downloads,.local/bin}


	echo '
# If running bash
if [ -n "$BASH_VERSION" ]; then

        # include .bashrc if it exists
        if [ -f "$HOME/.bashrc" ]; then
                . "$HOME/.bashrc"
   fi
fi

export EDITOR=/usr/bin/vim
#export QT_QPA_PLATFORM=wayland
export QT_IM_MODULE=Maliit
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export KWIN_IM_SHOW_ALWAYS=1

manager=''
default_manager=kde-dbus

if [[ -z $DISPLAY && $(tty) == /dev/tty1 && $XDG_SESSION_TYPE == tty ]]; then

#	read -t 2 -s -n1 -p "Press <w> to choose a window manager..." key;echo;echo;

	if [ "$key" = "w" ]; then
		if [ "$manager" = "choice" ] || [ "$manager" = "" ]; then
			echo -e "Choose a window manager:
		1. none
		2. weston
		3. kde
		4. kde-mobile
		5. gnome
		6. phosh
		7. kde (dbus)\n"
         read manager
      fi
	fi

	[ "$manager" = "" ] && manager=$default_manager

	case $manager in
		1|none)			;;
		2|weston)		exec weston --shell=desktop ;;
		3|kde)			startplasma-wayland ;;
		4|kde-mobile)	startplasmamobile ;;
		5|gnome)			MOZ_ENABLE_WAYLAND=1 gnome-session --session=gnome-wayland ;;
		6|phosh)			phosh-session ;;
 		7|kde-dbus)		/usr/lib/plasma-dbus-run-session-if-needed /usr/bin/startplasma-wayland ;;
	esac

fi

' > $mnt/home/$user/.bash_profile

	touch $mnt/home/$user/.hushlogin
	
	echo '[[ $- != *i* ]] && return
	
alias ls="ls --color=auto"
alias grep="grep --color=auto"
alias vi="vim"
alias arch="sudo /usr/local/bin/arch.sh"
PS1="$ "' > $mnt/home/$user/.bashrc

	cp $mnt/root/.vimrc $mnt/home/$user/.vimrc

	chown $user:$user $mnt/home/$user/{.vimrc,.hushlogin,.bash_profile,.bashrc}

	ls -la $mnt/home/$user

}



setup_iwd () {

	mount_disk


   #setup_dhcp


	pacstrap_install iw iwd
	
	mkdir -p $mnt/etc/iwd $mnt/var/lib/iwd

	echo '[General]
EnableNetworkConfiguration=true

[Scan]
DisablePeriodicScan=true' > $mnt/etc/iwd/main.conf

	if [[ ! $mnt = '' ]]; then
		[ -d /var/lib/dhcpcd ] && cp -r /var/lib/dhcpcd $mnt/var/lib/
		[ -d /var/lib/iwd ] && cp -r /var/lib/iwd $mnt/var/lib/
	fi

	echo "Enabling network services..."
	systemctl --root=$mnt enable iwd.service

}

setup_networkmanager () {

   mount_disk

   #setup_dhcp

   pacstrap_install networkmanager 
                              
   systemctl --root=$mnt enable NetworkManager.service
	
	#	echo "[device]
	#wifi.backend=iwd" > $mnt/etc/NetworkManager/conf.d/wifi_backend.conf
	
	if [[ -d /etc/NetworkManager ]] && [[ ! $mnt = '' ]]; then
		cp -r /etc/NetworkManager $mnt/etc/ 
	fi
}


setup_wpa () {

	mount_disk

	#setup_dhcp


	pacstrap_install iw wpa_supplicant


	systemctl --root=$mnt enable wpa_supplicant.service

	mkdir -p $mnt/etc/wpa_supplicant
	
	if [[ -d /etc/wpa_supplicant ]] && [[ ! $mnt = '' ]]; then
		cp -r /etc/wpa_supplicant $mnt/etc/ 
	fi

	systemctl --root=$mnt enable wpa_supplicant@wlo1.service

}



setup_dhcp () {

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


connect_wireless () {


   if [[ "$wifi_ssid" = "" ]] || [[ "$wifi_pass" = "" ]]; then
   	read -p "Please enter SSID: " $wifi_ssid
   	read -p "Please enter password: " $wifi_pass

	fi

   echo -e "\nWhich network manager would you like to connect to?\n"

   net_choices=(quit dhcpcd iwd wpa_supplicant networkmanager)
   select net_choice in "${net_choices[@]}"
   do
      case $net_choice in
         "quit")           break ;;
         "dhcp")           dhcpcd ;;
         "iwd")            

	iwctl station wlan0 scan

	while [ "$(iwctl station $wlan get-networks | grep 'No networks available')" ]; do
   	echo "Attempting to connected to $wlan..."
   	iwctl station $wlan get-networks
   	sleep 1
	done

	echo "$wlan connected!"

	echo "Waiting 5 seconds before connecting to $wlan..."
	sleep 5

	iwctl --passphrase $wifi_pass station $wlan connect $wifi_ssid
	echo "Waiting 5 seconds to ping..."
	sleep 5

	echo "Attempting to ping google.ca..."

	ping -c 1 -i 1 -q google.ca

									;;
         "wpa_supplicant") 

	interface=$(iw dev | awk '$1=="Interface"{print $2}')
	#interface=$(cat /proc/net/wireless | perl -ne '/(\w+):/ && print $1')
	
	wpa_passphrase "$wifi_ssid" "$wifi_pass" > /etc/wpa_supplicant/$interface.conf
	cp /etc/wpa_supplicant/$interface.conf /etc/wpa_supplicant/wpa_supplicant-$interface.conf
	#wpa_supplicant -B -i $interface -c <(wpa_passphrase $wifi_ssid $wifi_pass)

	systemctl enable wpa_supplicant@$interface.service
   systemctl start wpa_supplicant@$interface.service

			;;
         "networkmanager") 
										nmcli radio wifi on
										nmcli device wifi connect $wifi_ssid password $wifi_pass 
										;;
         '')               	echo -e "\nInvalid option!\n" ;;
      esac
   done

}



install_aur () {

	check_on_root
	mount_disk

# sudo cp /usr/lib/libalpm.so.15 /usr/lib/libalpm.so.13

	#pacstrap_install git less fakeroot pkg-config
	pacstrap_install git base-devel


	[ "$aur_app" = "paru" ] && pacstrap_install cargo
	#[ "$aur_app" = "none" ] && pacstrap_install cargo


#	arch-chroot $mnt /bin/bash << EOF
#
#cd $aur_path

#sudo -u $user git clone https://aur.archlinux.org/$aur_app.git

#cd $aur_app
#sudo -u $user makepkg -si

#sudo -u $user $aur_app --gendb

#chown -R $user:$user /home/$user/$aur_app

#EOF


	#[ "$aur_app" = "paru" ] && arch-chroot $mnt pacman -R rust
	#[ "$aur_app" = "yay" ] && arch-chroot $mnt pacman -R rust

	#rm -rf $mnt/home/$user/{.cargo,$aur_app/*} $mnt/usr/lib/{go,rustlib}
echo "To install an AUR package:

	sudo git clone https://aur.archlinux.org/<aur-package>.git
	cd <aur-package>
	makepkg -si"

}



setup_acpid () {

	mount_disk

	# Or install will generate an error: acpid: /usr/lib/systemd/system/acpid.service exists in filesystem
	rm -rf /usr/lib/systemd/system/acpid.service
	#pacstrap_install acpid cpupower htop power-profiles-daemon
	pacstrap_install acpid cpupower htop

		echo '[Unit]
Description=AC user power service

[Service]
ExecStart=/home/user/.local/bin/power.sh

[Install]
WantedBy=multi-user.target' > $mnt/etc/systemd/system/user-power.service

	ln -s -f $mnt/etc/systemd/system/user-power.service $mnt/etc/systemd/system/multi-user.target.wants/user-power.service


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
	ln -f -s $mnt/usr/lib/systemd/system/acpid.service $mnt/etc/systemd/system/multi-user.target.wants/acpid.service

}


timeshift_setup () {

	[ ! $timeshift_on = true ] || [ ! $fstype = btrfs ] && return 

	UUID=$(blkid -s UUID -o value $disk$rootPart)

	mkdir -p $mnt/etc/timeshift
	
	cat > $mnt/etc/timeshift/timeshift.json << EOF
{
  "backup_device_uuid" : "$UUID",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "true",
  "include_btrfs_home_for_backup" : "false",
  "include_btrfs_home_for_restore" : "false",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "false",
  "schedule_weekly" : "false",
  "schedule_daily" : "false",
  "schedule_hourly" : "true",
  "schedule_boot" : "false",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "5",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "date_format" : "%Y-%m-%d %H:%M:%S",
  "exclude" : [],
  "exclude-apps" : []
}
EOF

	pacstrap_install timeshift cronie grub-btrfs
	#systemctl daemon-reload

	systemctl --root=$mnt enable cronie.service
	systemctl --root=$mnt enable grub-btrfsd.service
	
	if [[ $mnt = '' ]]; then

	systemctl edit --stdin grub-btrfsd << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/grub-btrfsd --syslog -t
EOF
	systemctl daemon-reload
	#systemctl --root=$mnt restart grub-btrfsd.service

	else

		mkdir -p $mnt/etc/systemd/system/grub-btrfsd.service.d/override.conf.d
		echo '[Service]
ExecStart=
ExecStart=/usr/bin/grub-btrfsd --syslog -t' > $mnt/etc/systemd/system/grub-btrfsd.service.d/override.conf

	fi

}


install_tweaks () {

	mount_disk
	
	pacstrap_install terminus-font ncdu

	[ ! $(cat $mnt/etc/vconsole.conf | grep 'FONT=ter-132b') ] && echo 'FONT=ter-132b' >> $mnt/etc/vconsole.conf


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

	if [[ $linkedToTmp = true ]]; then
	
		# TODO: find out how to put all links in one variable
		rm -rf $mnt/var/log
   	rm -rf $mnt/var/tmp
   
		sync_disk
               
   	# TODO: find a way to create symbolic link from host
   	if [[ $mnt = '' ]]; then
   		ln -s $mnt/tmp $mnt/var/log
   		ln -s $mnt/tmp $mnt/var/tmp
   		chmod -R 1777 $mnt/var/tmp
		else 
      	arch-chroot $mnt ln -s /tmp /var/log
      	arch-chroot $mnt ln -s /tmp /var/tmp
			arch-chroot $mnt chmod -R 1777 /var/tmp
		fi
	
	fi

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
echo $password | sudo -u $user chsh -s /bin/mksh  # user shell
EOF

}


install_hooks () {

	mount_disk
	choice=$1

	if [[ $choice = '' ]]; then
		echo -e "What hooks would you like to install?\n\n1. liveroot \n2. overlayroot\n3. exit\n"
			read -p "Choice: " -n 2 choice
	else
		echo "Installing $choice hook..."
	fi

			
	case $choice in
		1|liveroot)		touch $mnt/etc/vconsole.conf
							pacstrap_install rsync squashfs-tools

							if [ "$fstype" = "btrfs" ]; then
								[ "$(cat $mnt/usr/lib/initcpio/install/liveroot | grep 'add_binary btrfs')" ] || sed -i 's/build() {/& \n        add_binary btrfs/g' $mnt/usr/lib/initcpio/install/liveroot
							fi

							echo 'MODULES=(lz4)
BINARIES=()
FILES=()
#HOOKS=(base udev keyboard autodetect kms modconf sd-vconsole block filesystems liveroot resume)
#HOOKS=(base udev keyboard autodetect kms modconf block filesystems liveroot resume)
#HOOKS=(autodetect base keyboard kms block udev filesystems fsck liveroot resume)
HOOKS=(base udev autodetect modconf kms consolefont keyboard keymap block filesystems fsck liveroot resume)
COMPRESSION="lz4"
COMPRESSION_OPTIONS=()
MODULES_DECOMPRESS="no"' > $mnt/etc/mkinitcpio.conf

							# So systemd won't remount as 'rw'
							#systemctl --root=$mnt mask systemd-remount-fs.service

							# Don't remount /efi either
							#systemctl --root=$mnt mask efi.mount
							;;
		2|overlayroot)	
							#https://aur.archlinux.org/packages/overlayroot
							#https://github.com/hilderingt/archlinux-overlayroot
	
							echo 'MODULES=(lz4 overlay)
BINARIES=()
FILES=()
#HOOKS=(base udev keyboard autodetect kms modconf sd-vconsole block filesystems liveroot resume)
#HOOKS=(base udev keyboard autodetect kms modconf block filesystems liveroot resume)
#HOOKS=(autodetect base keyboard kms block udev filesystems fsck liveroot resume)
HOOKS=(base udev autodetect modconf kms keyboard consolefont keymap block filesystems fsck resume overlayroot)
COMPRESSION="lz4"
COMPRESSION_OPTIONS=()
MODULES_DECOMPRESS="no"' > $mnt/etc/mkinitcpio.conf

							#	pacman --noconfirm -U /home/user/.local/bin/overlayroot*.zst

							echo -e "\nAdd 'overlayroot' to kernal parameters to run\n"
							;;
		*) echo -e "\nInvalid choice: $choice\n"; return ;;
	esac

	if [[ $mnt = '' ]]; then
		mkinitcpio -p linux 
	else
		arch-chroot $mnt mkinitcpio -p linux 
	fi

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


download_script () {

	echo -e "\nDowloading script from Github..."

	curl -sL https://raw.githubusercontent.com/bathtime/arch/main/arch.sh > $mnt/$arch_path/$arch_file
	chmod +x $mnt/$arch_path/$arch_file

}

clone () {

	check_on_root
	mount_disk

	check_pkg rsync

	echo -e "\n$1 $3 -> $4. Please be patient...\n"
	
	rsync_excludes=" --exclude=/run/timeshift/ --exclude=/etc/timeshift/timeshift.json --exclude=/etc/fstab --exclude=/etc/default/grub --exclude=/root.squashfs --exclude=/lost+found/ --exclude=/.snapshots/ --exclude=/dev/ --exclude=/proc/ --exclude=/sys/ --exclude=/tmp/ --exclude=/run/ --exclude=/var/tmp/ --exclude=/var/lib/dhcpcd/ --exclude=/var/log/ --exclude=/var/lib/systemd/random-seed --exclude=/root/.cache/ --exclude=/media/ --exclude=/mnt/ --exclude=/home/$user/.cache/ --exclude=/home/$user/.local/share/Trash/ --exclude=/snapshots/"


	rsync --dry-run -v $2 $rsync_excludes $3 $4 | less

	echo -e "\nType 'y' to proceed with rsync or any other key to exit..."
	read choice

	if [[ $choice = y ]]; then

		echo -e "\nRunning rsync...\n"
	
		rsync $2 --info=progress2 $rsync_excludes $3 $4
		#tar -C $3 -cf - . | tar -C $4 -xf -

		arch-chroot $mnt pacman -S --noconfirm linux	
  		install_grub
		choose_initramfs dracut
		choose_initramfs booster 
		setup_fstab
		fs_packages
		timeshift_setup

	else
		echo "Exiting."
	fi

}


take_snapshot () {

	mount_disk
	
	filename=$(date +"%Y-%m-%d @ %H:%M:%S")
	
	echo -e "\nList of snapshots:\n"
	ls -1N $mnt$snapshot_dir/

	if [[ $1 = '' ]]; then
		echo -e "\n\nWhat would you like to call this snapshot?\n"
		read snapshotname
	else
		snapshotname="$1"
	fi

	[[ ! $snapshotname = '' ]] && snapshotname=" - $snapshotname"

	if [[ $fstype = bcachefs ]]; then
		bcachefs subvolume snapshot "$mnt$snapshot_dir/$filename$snapshotname"
	fi
	if [[ $fstype = btrfs ]]; then
		btrfs subvolume snapshot $mnt/ "$mnt$snapshot_dir/$filename$snapshotname"
	fi

	echo -e "\nCreated snapshot: $mnt$snapshot_dir/$filename$snapshotname\n"	
	
	ls -1N $mnt$snapshot_dir/
	echo

	# To update grub to include bootable snapshots	
	if [[ $fstype = btrfs ]]; then

	   if [[ $mnt = '' ]]; then
      	grub-mkconfig -o $mnt/boot/grub/grub.cfg
   	else
      	arch-chroot $mnt grub-mkconfig -o /boot/grub/grub.cfg
   	fi

	fi

}


restore_snapshot () {

	mount_disk	

	echo -e "\nWhich snapshot would you like to recover?\n"

	cd $mnt$snapshot_dir
	
   select snapshot in *
      do
         case snapshot in
         *) echo -e "\nYou chose: $snapshot\n"; break ;;
      esac
   done

	if [ -d "$mnt$snapshot_dir/$snapshot" ] && [ ! "$snapshot" = '' ]; then

		echo -e "\nRunning dry run first..."
		sleep 1

		#-a  : all files, with permissions, etc..
		#-v  : verbose, mention files
		#-x  : stay on one file system
		#-H  : preserve hard links (not included with -a)
		#-A  : preserve ACLs/permissions (not included with -a)
		#-X  : preserve extended attributes (not included with -a)
		#-S  : handle sparse files efficiently
		#-W  : improve the copy speed by not calculating deltas/diffs of the files
		#---numeric-ids : avoid mapping uid/gid values by user/group name
		#--info=progress2 : instead of --progress is useful for large transfers
		# arch recommended: -aAXHv

		rsync_params="-axHAXvSW --del --exclude=/etc/timeshift/timeshift.json --exclude=/run/timeshift/ --exclude=/lost+found/ --exclude=/.snapshots/ --exclude=/dev/ --exclude=/proc/ --exclude=/sys/ --exclude=/tmp/ --exclude=/run/ --exclude=/var/tmp/ --exclude=/var/lib/dhcpcd/ --exclude=/var/log/ --exclude=/var/lib/systemd/random-seed --exclude=/root/.cache/ --exclude=/boot/ --exclude=/efi/ --exclude=/media/ --exclude=/mnt/ --exclude=/home/$user/.cache/ --exclude=/home/$user/.local/share/Trash/ --exclude=$mnt/ --exclude=/snapshots/"
		
		rsync --dry-run $rsync_params "$mnt$snapshot_dir/$snapshot/" $mnt/ | less

		echo -e "\nType 'y' to proceed with rsync or any other key to exit..."
		read choice

		if [[ $choice = y ]]; then

			echo -e "\nRunning rsync...\n"
			rsync $rsync_params --info=progress2 "$snapshot_dir/$snapshot/" /
	
		else
			echo "Exiting."
		fi

	else
		echo "Snapshot directory does not exist. Exiting."
	fi

}


delete_snapshot () {

	mount_disk	

	echo -e "\nWhich snapshot would you like to delete?\n"

	cd $mnt$snapshot_dir
	
   select snapshot in *
	do
		case snapshot in
         *) echo -e "\nYou chose: $snapshot\n"; break ;;
      esac
   done

	if [ -d "$mnt$snapshot_dir/$snapshot" ] && [ ! "$snapshot" = '' ]; then

		btrfs subvolume delete "$mnt$snapshot_dir/$snapshot"

	else
		echo "Snapshot directory does not exist. Exiting."
	fi

}


delete_timeshift_snapshots () {

	ls -la /run/timeshift/*/backup/timeshift-btrfs/snapshots/

	if [ -d /run/timeshift/*/backup/timeshift-btrfs/snapshots/ ]; then
		
		echo -e "\nDeleting timeshift backup snapshots. Please be patient...\n"

		btrfs subvolume delete $mnt/run/timeshift/*/backup/timeshift-btrfs/snapshots/*/@/	
		rm -rf /run/timeshift/*/backup/timeshift-btrfs/snapshots/
	
	else
		echo -e "\nNo backup snapshots.\n"
	fi

}


rsync_snapshot () {

	mount_disk	

	mkdir -p $mnt$snapshot_dir

	echo -e "\nList of snapshots:\n"
	ls -1N $mnt$snapshot_dir/

	if [[ $1 = '' ]]; then
		echo -e "\n\nWhat would you like to call this rsync snapshot?\n"
		read snapshotname
	else
		snapshotname="$1"
	fi


		echo -e "\nRunning dry run first..."
		sleep 1

		rsync_params="-axHAXSW --del --exclude=/run/timeshift/ --exclude=/etc/timeshift/timeshift.json --exclude=/lost+found/ --exclude=/.snapshots/ --exclude=/dev/ --exclude=/proc/ --exclude=/sys/ --exclude=/tmp/ --exclude=/run/ --exclude=/var/tmp/ --exclude=/var/lib/dhcpcd/ --exclude=/var/log/ --exclude=/var/lib/systemd/random-seed --exclude=/root/.cache/ --exclude=/boot/ --exclude=/efi/ --exclude=/media/ --exclude=/mnt/ --exclude=/home/$user/.cache/ --exclude=/home/$user/.local/share/Trash/ --exclude=$mnt/ --exclude=/snapshots/"
		
		rsync --dry-run -v $rsync_params / "$mnt$snapshot_dir/$snapshotname" | less

		echo -e "\nType 'y' to proceed with rsync or any other key to exit..."
		read choice

		if [[ $choice = y ]]; then

			echo -e "\nRunning rsync...\n"
			rsync $rsync_params --info=progress2 / "$snapshot_dir/$snapshotname"
	
		else
			echo "Exiting."
		fi

}


bork_system () {

	if [[ $mnt = '' ]]; then
		pacman -Rnsc plasma
	else
		arch-chroot $mnt pacman -Rnsc -noconfirm plasma 
	fi

	rm -rf $mnt/etc

}



extract_archive () {

	check_on_root
	mount_disk

	unsquashfs -d $mnt -f /root.squashfs

}



create_archive () {


	check_pkg squashfs-tools


	echo "Creating archive file..."

	cd / 
	rm -rf /root.squashfs
	
	#time mksquashfs / root.squashfs -mem-percent 50 -no-recovery -noappend -e /boot/ -e /efi/ -e root.squashfs -e /dev/ -e /proc/ -e /sys -e /tmp/ -e /run -e /mnt -e $snapshot_dir/ -e /home/$user/.cache/ -e /setup.tar -e /var/cache/pacman/ -e /root/.cache/ -e /run/timeshift/ -e /var/tmp/ -e /var/log/ -e /etc/pacman.d/gnupg/ -e /home/$user/.local/share/Trash/ -e /usr/share/doc/ -e /usr/share/man/ -e /usr/share/wallpapers -e /usr/share/gtk-doc -e /usr/share/fonts/noto -e /usr/lib/firmware/nvidia -e /usr/lib/firmware/amdgpu -comp lz4  
	
	#time mksquashfs / root.squashfs -mem-percent 50 -no-recovery -noappend -e /boot/ -e /efi/ -e root.squashfs -e /dev/ -e /proc/ -e /sys -e /tmp/ -e /run -e /mnt -e $snapshot_dir/ -e /home/$user/.cache/ -e /setup.tar -e /var/cache/pacman/ -e /root/.cache/ -e /run/timeshift/ -e /var/tmp/ -e /var/log/ -e /etc/pacman.d/gnupg/ -e /home/$user/.local/share/Trash/ -e /usr/share/doc/ -e /usr/share/man/ -e /usr/share/wallpapers -e /usr/share/gtk-doc -e /usr/share/fonts/noto -e /usr/lib/firmware/nvidia -e /usr/lib/firmware/amdgpu -comp gzip
	
	#time mksquashfs / root.squashfs -mem-percent 50 -no-recovery -noappend -e root.squashfs -e /dev/ -e /proc/ -e /sys -e /tmp/ -e /run -e /mnt -e $snapshot_dir/ -e /home/$user/.cache/ -e /root/.cache/ -e /run/timeshift/ -e /var/tmp/ -e /var/log/ -e /home/$user/.local/share/Trash/ -comp gzip
	
	time mksquashfs / root.squashfs -comp lz4 -mem-percent 25 -no-recovery -noappend -e root.squashfs -e /dev/ -e /proc/ -e /sys -e /tmp/ -e /run -e /mnt -e $snapshot_dir/ -e /home/$user/.cache/ -e /root/.cache/ -e /var/tmp/ -e /var/log/ -e /home/$user/.local/share/Trash/

	ls -lah root.squashfs

	#lzma	2m21	2.3G
	#xz	2m34	2.3G
	#zstd	1m18	2.4G
	#gzip 50s	2.5G
	#lzo	1m13s	2.6G
	#lz4  5.5s	2.8G
	#none 6s		4.2G (-no-compression)

}



install_network () {

	echo -e "\nWhich network manager would you like to install?\n"
		
	net_choices=(quit dhcp iwd wpa_supplicant networkmanager) 
	select net_choice in "${net_choices[@]}"
	do
		case $net_choice in
			"quit")				break ;;
			"dhcp")				setup_dhcp; break ;;
			"iwd")				setup_iwd; break ;;
			"dhcp")				setup_dhcp; break ;;
			"wpa_supplicant")	setup_wpa; break ;;
			"networkmanager") setup_networkmanager; break ;;
			'')					echo -e "\nInvalid option!\n" ;;
		esac
	done

}



install_bootloader () {

	echo -e "\nWhich boot manager would you like to install?\n"

	choiceBoot=(grub rEFInd EFISTUB uki systemD quit) 
				
	select choiceBoot in "${choiceBoot[@]}"
	do
		case $choiceBoot in
			"grub")		install_grub; break ;;
			"rEFInd")	install_REFIND; break ;;
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
				echo "Package: $package already installed."
			fi

		done

	fi

	if [[ "$packages" ]]; then

		if [[ "$mnt" = '' ]]; then
			pacman --noconfirm --needed -S ${packages[@]}
		else

			if [ "$copy_on_host" -eq 1 ] && [ ! "$(pacman -Q $package 2>/dev/null)" ]; then
				pacman --needed --noconfirm -S ${packages[@]}
			fi

			if [ "$offline" -eq 1 ]; then
				pacstrap -C /etc/pacman-offline.conf -c -K $mnt ${packages[@]}
			else

				# Ideal when using an arch install disk in ram
				if [ "$copy_on_host" -eq 0 ]; then
					pacstrap -K $mnt ${packages[@]}
				else
					pacstrap -c -K $mnt ${packages[@]}
				fi

			fi
		fi
	fi
}



custom_install () {

	#check_on_root
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

	#echo -e "\n/var/cache/pacman/pkg/* contains:"
	
	echo -e "\nTotal packages: $(ls $mnt/var/cache/pacman/pkg/*.zst | wc -l)\n"

	#echo -e "\nTotal packages: $(ls $mnt/var/cache/pacman/pkg/*.zst | wc -l)\n"
	#echo -e "Total files: $(ls $mnt/var/cache/pacman/pkg/* | wc -l)\n"

	#echo -e "\nUpdating package database. Please be patient...\n"

	#pacman-db-upgrade

	#repo-add -q -n /var/cache/pacman/pkg/./custom.db.tar.gz /var/cache/pacman/pkg/*.zst
	#repo-add -q -n $mnt/var/cache/pacman/pkg/./custom.db.tar.gz $mnt/var/cache/pacman/pkg/*.zst

	#pacman -U /mnt/var/cache/pacman/pkg/*.pkg.tar.zst
	#pacman -U /var/cache/pacman/pkg/*.pkg.tar.zst

	#echo -e "\nCopying AUR directory. Please be patient...\n"

}



update_mirrorlist () {

	#check_pkg reflector
	#echo -e "\nRunning reflector...\n"
	#reflector > /etc/pacman.d/mirrorlist
	
	echo -e "\nUpdating mirror list. Please be patient...\n"

	curl -s "https://archlinux.org/mirrorlist/?country=CA&country=US&protocol=https&use_mirror_status=on" | sed -e 's/^#Server/Server/' -e '/^#/d' | rankmirrors -n 10 - > /etc/pacman.d/mirrorlist

	cat /etc/pacman.d/mirrorlist
}



check_online () {

	curl -Is  http://www.google.com &>/dev/null && online=1 || online=0

	if [ $online -eq 0 ]; then
		echo -e "\nNo internet connection found. Offline mode enabled."
		offline=1 
	fi

}


backup () {

	if [[ $backup_install = true ]]; then

		if [[ $fstype = bcachefs ]]; then 
			
			take_snapshot "$1"
		
		elif [[ $fstype = btrfs ]]; then
			
			if [[ $timeshift_on = true ]]; then
				arch-chroot $mnt timeshift --create --comments "$1" --tags D
  				arch-chroot $mnt grub-mkconfig -o /boot/grub/grub.cfg
			else
				take_snapshot "$1"
			fi

		fi

	fi

}


auto_install_root () {

	create_partitions

	setup_fstab
	install_base

	if [[ $autologin = true ]]; then
		auto_login root
	fi

	#setup_fstab
	install_grub
	
	# Bootable snapshots will not work with mkinitcpio
	if [[ $fstype = btrfs ]]; then
		choose_initramfs booster
		choose_initramfs dracut
	else
		choose_initramfs $initramfs
	fi

	general_setup
	
	#setup_iwd
	setup_networkmanager
	#setup_wpa
	
	install_tweaks
	copy_script
	copy_pkgs
	
	timeshift_setup

	backup "Root installed"

}


auto_install_user () {

	auto_install_root
	
	pacstrap_install $user_install
	
	setup_user

	pacstrap_install sudo

	if [[ $autologin = true ]]; then
		auto_login $user
	fi

	# Auto-launch
	sed -i 's/manager=.*$/manager=none/g' $mnt/home/$user/.bash_profile

	#install_aur
	#setup_acpid
	
	copy_pkgs
	backup "User installed"

}


auto_install_kde () {

	auto_install_user
 
	pacstrap_install $kde_install

	copy_pkgs

	# Auto-launch
	sed -i 's/manager=.*$/manager=kde/g' $mnt/home/$user/.bash_profile

	install_config
	install_hooks overlayroot

	backup "KDE installed"

}


auto_install_gnome () {

	auto_install_user
	
	pacstrap_install $gnome_install
 
	copy_pkgs

	# Auto launch
	sed -i 's/manager=.*$/manager=gnome/g' $mnt/home/$user/.bash_profile

	install_config
	backup "Gnome installed"

}


auto_install_gnomekde () {

	auto_install_user

	pacstrap_install $gnome_install $kde_install
	
	copy_pkgs

	# Customize system

	sed -i 's/manager=.*$/manager=choice/g' $mnt/home/$user/.bash_profile

	install_config
	backup "Gnome and KDE installed"

}


auto_install_cage () {

	auto_install_user
	
	pacstrap_install $cage_install

	copy_pkgs

	# Auto launch
	sed -i 's/manager=.*$/manager=cage/g' $mnt/home/$user/.bash_profile

	install_config

	backup "Cage installed"

}



auto_install_weston () {

	auto_install_user

	pacstrap_install $weston_install

	copy_pkgs
	
	sed -i 's/manager=.*$/manager=weston/g' $mnt/home/$user/.bash_profile

	install_config
	backup "Weston installed"

}


auto_install_phosh () {

	auto_install_user
	
	pacstrap_install $phosh_install

	copy_pkgs

	# Auto launch
	sed -i 's/manager=.*$/manager=phosh/g' $mnt/home/$user/.bash_profile

	install_config
}


auto_install_all () {

	auto_install_user
	
	pacstrap_install $gnome_install $kde_install $weston_install

	copy_pkgs

	# Customize system

	sed -i 's/manager=.*$/manager=choice/g' $mnt/home/$user/.bash_profile

	install_config
}


install_snapper () {
	
	mount_disk


   if [[ $mnt = '' ]]; then

		umount /.snapshots
		rm -rf /.snapshots

		snapper -c config create-config /

		btrfs su delete /.snapshots
		mkdir /.snapshots
		mount -o subvol=@snapshots $disk$rootPart /.snapshots

		genfstab -U /

		mount -a
		
		chmod 750 /.snapshots

	else

		#arch-chroot $mnt btrfs su list /
		#arch-chroot $mnt btrfs su create /.snapshots

		rm -rf $mnt/.snapshots
		
		#pacstrap_install snapper
		pacstrap_install snapper
		
#		arch-chroot $mnt btrfs su create /.snapshots

		#UUID=76526f43-5af2-4bb3-a606-253c327aab62 /.snapshots          btrfs       rw,noatime,ssd,discard=async,space_cache=v2,subvol=/@/.snapshots  0 0
	
#		cat $mnt/etc/fstab | sed 's#subvol=/@\s#subvol=/@/.snapshots #' | grep snapshots | sed 's#/.*btrfs#/.snapshots  btrfs##' >> $mnt/etc/fstab	
		
#		cat $mnt/etc/fstab
#		systemctl daemon-reload	
#		mount -a

		arch-chroot $mnt btrfs subvolume list /
		
#		read -p "How does it look?"

		return


		umount $mnt$snapshot_dir
		rm -rf $mnt$snapshot_dir
		rm -rf $mnt/.snapshots
		
		# Will always repopulate so no use deleting them
		arch-chroot $mnt btrfs su delete --subvolid $(btrfs su list / | grep var/lib/portables | sed 's/ID //; s/ gen.*//') $mnt
		arch-chroot $mnt btrfs su delete --subvolid $(btrfs su list / | grep var/lib/machines | sed 's/ID //; s/ gen.*//') $mnt
		arch-chroot $mnt btrfs su delete --subvolid $(btrfs su list / | grep snapshots | sed 's/ID //; s/ gen.*//') $mnt

		arch-chroot $mnt btrfs subvolume list /
		read -p "Press any key to continue."

		# Already covered so no need?
		arch-chroot $mnt snapper -c root create-config /
		
		arch-chroot $mnt btrfs subvolume list /

   fi
	

}


clean_system () {

	#echo "Cleaning unused locales..."
	#ls /usr/share/locales/ | grep -xv "en_US" | xargs rm -r


	echo "Cleaning ~/.cache..."
	rm -rf /home/user/.cache/*
	

	echo "Cleaning brave..."

	rm -rf /home/$user/.config/BraveSoftware/Brave-Browser/component_crx_cache/* rm -rf /home/user/.config/BraveSoftware/Brave-Browser/Default/Service\ Worker/CacheStorage/*

	echo "Cleaning mozilla..."

	cd /home/$user/.mozilla/firefox
	rm -rf 'Crash Reports' 'Pending Pings'

	rm -rf /usr/lib/firefox/crashreporter /usr/lib/firefox/minidump-analyzer /usr/lib/firefox/pingsender

	profile=$(ls /home/user/.mozilla/firefox/ | grep .*.default-release)
	cd $profile

	rm -rf crashes minidumps datareporting sessionstore-backups saved-telemetry-pings storage browser-extension-data security_state gmp-gmpopenh264 synced-tabs.db-wal places.sqlite favicons.sqlite cert9.db places.sqlite-wal storage-sync-v2.sqlite-wal webappsstore.sqlite gmp-widevinecdm
	

	rm -rf storage/default 'Crash Reports/events' webappsstore.sqlite formhistory.sqlite sessionCheckpoints.json sessionstore.jsonlz4 sessionstore-backups content-prefs.sqlite places.sqlite favicons.sqlite storage.sqlite storage-sync-v2.sqlite bounce-tracking-protection.sqlite permissions.sqlite protections.sqlite cookies.sqlite cookies.sqlite-wal 


	#echo "Cleaning chromium..."

	#cd /home/$user/.config/chromium

	#rm -rf Safe\ Browsing component_crx_cache WidevineCdm IndexedDB GrShaderCache OnDeviceHeadSuggestModel hyphen-data ZxcvbnData ShaderCache Default/{Service\ Worker/,IndexedDB,History,GPUCache,Sessions,DawnCache,Extension\ State,Web\ Data,Visited\ Links}
	#rm -rf Safe\ Browsing component_crx_cache WidevineCdm GrShaderCache OnDeviceHeadSuggestModel hyphen-data ZxcvbnData ShaderCache Default/{Service\ Worker/,History,GPUCache,Sessions,DawnCache,Extension\ State,Web\ Data,Visited\ Links}

}



backup_config () {

	echo -e "\nYou may wish to clean your system first!\n"

	cd /
	rm -rf setup.tar

	#sudo -u $user tar -pcf setup.tar $CONFIG_FILES
	

	#tar -pcf setup.tar $CONFIG_FILES

	rm -rf /home/$user/.local/share/Trash/*
	tar -pcf setup.tar $CONFIG_FILES
	

	#chown $user:$user /home/$user/setup.tar
	chown -R $user:$user /home/$user/

	#sudo -u $user gpg --yes -c setup.tar
	#ls -lah setup.tar setup.tar.gpg
	
	ls -lah setup.tar

}



restore_config () {

	mount_disk
	
	cd $mnt/

	echo "Extracting setup file..."
	tar xvf /setup.tar
	chown -R $user:$user $mnt/home/$user/

}



install_config () {

	check_on_root
	mount_disk

	#read -p "Press any key when ready to enter password."
	#echo "Decrypting setup file..."
	#gpg --yes --output /home/$user/setup.tar --decrypt /home/$user/setup.tar.gpg


	#cp /home/$user/setup.tar{,.gpg} $mnt/home/$user/
	cp /setup.tar $mnt/

	echo "Extracting setup files..."
	arch-chroot $mnt tar xvf /setup.tar --directory /
	arch-chroot $mnt chown -R $user:$user /home/$user/

	count=`ls -1 /home/user/.local/bin/*.zst 2>/dev/null | wc -l`

	if [ $count != 0 ]; then

		echo -e "\nInstalling extra packages...\n"
	
		if [[ $mnt = '' ]]; then
			sudo pacman -U --noconfirm /home/user/.local/bin/*.zst
			# Fix shared libraries error
			sudo ln -s /usr/lib/libalpm.so.15 /usr/lib/libalpm.so.13
		else
			arch-chroot $mnt sudo pacman -U --noconfirm /home/user/.local/bin/*.zst
   		arch-chroot $mnt ln -s /usr/lib/libalpm.so.15 /usr/lib/libalpm.so.13
		fi

	fi

}



last_modified () {

	find / -cmin -1 -printf '%t %p\n' | sort -k 1 -n | cut -d' ' -f2- | grep -v /proc

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

		error_bypass=1
		time dd if=/dev/$1 of=$disk bs=1M status=progress
		error_bypass=0

	else
		echo -e "\nNot wiping.\n"
	fi

}


clean () {

	echo -e "\nCleaning files...\n"
	rm -rfv		/var/log /var/tmp /tmp/{*,.*} /home/$user/.cache/{*,.*} \
					/root/.cache/{*,.*} /root/.bash_history 

	echo
	echo -e "\nClearing pagecache, dentries, and inodes...\n\nBefore:"
	free -h
	sudo sync; echo 3 > /proc/sys/vm/drop_caches
	echo -e "\nAfter:"
	free -h

}


wipe_freespace () {

	echo -e "\nWiping freespace on $disk using zero method. Please be patient...\n"
	echo -e "Run 'watch -n 1 -x df / --sync' in another terminal to see progress.\n"

	error_bypass=1

	cd /

	file=$(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 32).tmp
	(dd if=/dev/zero of=$file bs=4M status=progress; dd if=/dev/zero of=$file.small bs=256 status=progress) &>/dev/null


	sync ; sleep 60 ; sync
	rm $file $file.small

	error_bypass=0

}



disk_info () {

	echo -ne "\nDisk: $(lsblk --output=PATH,SIZE,MODEL,TRAN -dn $disk) "

	if [[ "$mounted_on" = "" ]]; then
		echo "(unmounted)"
	elif [[ "$mounted_on" = "/" ]]; then
		echo "(host)"
	else
		echo "(mounted on $(lsblk -no MOUNTPOINT $disk$rootPart))"
	fi

   echo "File type: $fstype"

}



sync_disk () {

	echo -e "\nSyncing disk. Please be patient...\n"
	sync

	return

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
		
		# If it's taking too long, it might be stuck and need to be resynced
		if [ $stall_count -gt 50 ]; then
			sync &
			stall_count=0
			echo "Resyncing..."
		fi

		sleep .1

	done

	echo
	sleep .5

}


aur_package_install () {

	check_on_root
	mount_disk

	#aur_app=brave-bin
	#aur_git='https://aur.archlinux.org/brave-bin.git'

	aur_app="$1"
	aur_git="$2"

	echo -e "Copying $aur_path/$aur_app..."

	mkdir -p $mnt$aur_path
	
	cp -r $aur_path/$aur_app $mnt$aur_path	
	chown -R user:user $mnt$aur_path
	ls -la $mnt$aur_path

	echo -e "Finished!"


		arch-chroot $mnt /bin/bash << EOF

	cd $aur_path

	sudo -u $user git clone $aur_git

	cd $aur_app
	sudo -u $user makepkg -sf

	echo "Installing $aur_path/$aur_app/$aur_app-*.zst..."
	pacman -U $aur_path/$aur_app/$aur_app-*.zst

EOF

}


benchmark () {
		
	mount_disk

	tempfile="$mnt/bench.tmp"

	cd $mnt/
	rm -rf $tempfile

	echo -e "\nRunning dd to measure write speed...\n"
	dd if=/dev/zero of=$tempfile bs=1M count=1024 conv=fdatasync,notrunc status=progress

	echo 3 > /proc/sys/vm/drop_caches
	echo -e "\nRunning dd to measure read speed...\n"
	dd if=$tempfile of=/dev/null bs=1M count=1024 status=progress

	echo -e "\nRunning dd to measure buffer-cache speed...\n"
	dd if=$tempfile of=/dev/null bs=1M count=1024 status=progress

	echo -e "\nRunning bash open/close test to measure buffer-cache speed..."
	time for (( i=1; i<=1000; i++ )); do bash -c 'exit' ;done

	rm $tempfile
	

	echo -e "\nPress any key to continue."
	read -s -N 1
	echo

}


install_group () {

	config_choices=("1. Quit
2. kde
3. gnome")			

	config_choice=0

	while [ ! "$config_choice" = "1" ]; do

		echo
		echo "${config_choices[@]}" | column
		echo  

		read -p "Which option? " config_choice

   	case $config_choice in
   		quit|1)		echo "Quitting!"; break; ;;
   		kde|2)		pacstrap_install $kde_install ;;
   		gnome|3)		pacstrap_install $gnome_install ;;
   		'')			last_modified ;;
   		*)				echo -e "\nInvalid option ($config_choice)!\n" ;;
		esac

	done

}



clone_menu () {
	
	config_choices=("1. Quit to main menu
2. Unsquash to target
3. Part + Clone / -> $disk
4. Clone / -> $disk
5. Clone $disk -> /
6. Copy / -> $disk
7. Copy $disk -> /
8. Copy /home -> $disk$rootPart/
9. Copy $disk$rootPart/home -> /
10. Update / <-> $disk
11. Wipe (zero)
12. Wipe (urandom)
13. Wipe freespace     
14. Shred $disk
15. Create squashfs image
16. Take btrfs/bcachefs snapshot
17. Restore btrfs/bcachefs snapshot
18. Delete btrfs/bcachefs snapshot
19. Rsync snapshot
20. Bork system
21. Delete timeshift backups")

	config_choice=0
	while [ ! "$config_choice" = "1" ]; do

		echo
		echo "${config_choices[@]}" | column
		echo  

		read -p "Which option? " config_choice

		case $config_choice in
			quit|1)			echo "Quitting!"; break ;;
			unsquash|2)		extract_archive ;;
			clone|3)			create_partitions
								time clone Cloning '-aSW --del' / $mnt/ ;;
			clone|4)			time clone Cloning '-aSW --del' / $mnt/ ;; 
			clone|5)			clone Cloning '-aSW --del' $mnt/ / ;;
			copy|6)			clone Copying -aSW / $mnt/ ;;
			copy|7)			clone Copying -aSW $mnt/ / ;;
			copy|8)			clone Copying -aSW /home $mnt/ ;;
			copy|9)			clone Copying -aSW $mnt/home / ;;
			update|10)		clone Updating -auSW / $mnt/
								clone Updating -auSW $mnt/ / ;;
			wipe|11)			wipe_disk zero ;;
			wipe|12)			wipe_disk urandom ;;
			wipe-free|13)	wipe_freespace ;;
			shred|14)		unmount_disk; shred -n 1 -v -z $disk ;;
			squashfs|15)	create_archive ;;
			snapshot|16)	take_snapshot ;;
			restore|17)		restore_snapshot ;;
			delete|18)		delete_snapshot ;;
			rsync|19)		rsync_snapshot ;;
			bork|20)			bork_system ;;
			timeshift|21)	delete_timeshift_snapshots ;;
      	'')				;;
      	*)					echo -e "\nInvalid option ($config_choice)!\n" ;;
		esac

	done 

}


setup_menu () {

	config_choices=("1. Quit
2. Backup config
3. Restore config
4. Install config
5. Cleanup system
6. Last modified
7. Copy config
8. Copy packages")			config_choice=0

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
			copy|7)		echo "Copying packages from /setup.tar to $mnt/..."
							cp /setup.tar $mnt/ ;;
			pkgs|8)		copy_pkgs ;;
         '')			last_modified ;;
         *)				echo -e "\nInvalid option ($config_choice)!\n" ;;
		esac

	done 

}


packages_menu () {

	config_choices=("1. Quit to main menu
2. Reset pacman keys
3. Update mirror list
4. Copy packages
5. Download script
6. Copy script")

	config_choice=0
	while [ ! "$config_choice" = "1" ]; do

		echo
		echo "${config_choices[@]}" | column
		echo  

		read -p "Which option? " config_choice

   	case $config_choice in
   		quit|1)				echo "Quitting!"; break ;;
			reset|keys|2)		reset_keys ;;
			mirrorlist|3)		update_mirrorlist ;;
			pkgs|4)				copy_pkgs ;;
			script|5)			download_script ;;
			copy_script|6)		copy_script ;;
   		'')					last_modified ;;
			*)						echo -e "\nInvalid option ($config_choice)!\n" ;;
		esac

	done

}


auto_install_menu () {
	
	config_os=("1. Quit
2. Root
3. User
4. Weston
5. KDE
6. Gnome
7. Phosh
8. Cage
9. Gnome/Kde
10. All")

	echo
	echo "${config_os[@]}" | column
	echo  

	read -p "Which option? " config_os

   case $config_os in
   	quit|1)			;;
   	root|2)			time auto_install_root ;;
   	user|3)			time auto_install_user ;;
   	weston|4)		time auto_install_weston ;;
   	kde|5)			time auto_install_kde ;;
   	gnome|6)			time auto_install_gnome ;;
   	phosh|7)			time auto_install_phosh ;;
   	cage|8)			time auto_install_cage ;;
		gnomekde|9)		time auto_install_gnomekde ;;
      all|10)			time auto_install_all ;;
     	'')				;;
	  	*)					echo -e "\nInvalid option ($config_os)!\n" ;;
	esac

}


#/etc/mkinitcpio.conf
#/etc/NetworkManager/conf.d/dhcp-client.conf
#/etc/NetworkManager/conf.d/wifi_backend.conf

CONFIG_FILES2="

/usr/bin/librewolf
/usr/lib/librewolf

/home/$user/.librewolf"


CONFIG_FILES="

/usr/lib/initcpio/install/liveroot
/usr/lib/initcpio/hooks/liveroot

/etc/overlayroot.conf
/usr/bin/mount.overlayroot
/usr/lib/initcpio/hooks/overlayroot
/usr/lib/initcpio/install/overlayroot

/etc/booster.yaml
/etc/default/grub-btrfs/config
/etc/dracut.conf.d/
/etc/hostname
/etc/hosts
/etc/iwd/main.conf
/etc/locale.conf
/etc/locale.gen
/etc/localtime
/etc/NetworkManager/conf.d/
/etc/NetworkManager/system-connections
/etc/pacman.conf
/etc/pacman-offline.conf
/etc/pacman.d/mirrorlist
/etc/security/limits.conf
/etc/sudoers.d/
/etc/sysctl.d/50-coredump.conf
/etc/sysctl.d/99-cache-pressure.conf
/etc/sysctl.d/99-net-keepalive.conf
/etc/sysctl.d/99-net-timeout.conf
/etc/sysctl.d/99-swappiness.conf
/etc/systemd/coredump.conf.d/custom.conf
/etc/systemd/system/getty@tty1.service.d/autologin.conf
/etc/systemd/system/user-power.service
/etc/udev/rules.d/powersave.rules
/etc/vconsole.conf
/etc/wpa_supplicant
/var/lib/dhcpcd
/var/lib/iwd
/usr/lib/systemd/system-sleep/sleep.sh

/home/$user/.bash_profile
/home/$user/.bashrc
/home/$user/.config/
/home/$user/.hushlogin
/home/$user/.local/
/home/$user/.vimrc"


if [ "$1" ]; then
	disk="$1"
else
	choose_disk
fi

check_viable_disk

disk_info

check_online


while :; do

	choices=("1. Back to main menu 
2. Edit $arch_file
3. Chroot
4. Auto-install
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
16. Install hooks
17. Setup acpid
18. Choose initramfs
19. Mount $mnt
20. Unmount $mnt
21. Update grub
22. Connect wireless
23. Install snapper
24. Packages/script
25. Timeshift
26. Auto-login root
27. Auto-login user
30. Custom install
31. Setup ~ files
32. Snapshot/sync/wipe ->
33. Install aur packages ->
34. Install group packages ->
35. Benchmark")


echo
echo "${choices[@]}" | column   

echo -ne "\nEnter an option: "

read choice

echo

	case $choice in
		Quit|quit|q|exit|1)	choose_disk ;;
		arch|2)					edit_arch ;;
		Chroot|chroot|3)		do_chroot ;;
		auto|4)					auto_install_menu ;;
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
		hooks|16)				install_hooks ;;
		acpid|17)				setup_acpid ;;
		initramfs|18)			choose_initramfs ;;
      mount|19)				mount_disk  ;;
      unmount|20)				unmount_disk  ;;
		grub|21)					grub-mkconfig -o $mnt/boot/grub/grub.cfg ;;
		connect|iwd|22)		connect_wireless ;;
		snapper|23)				install_snapper ;;
		packages|24)			packages_menu ;;
		timeshift|25)			timeshift_setup ;;
		loginroot|26)			auto_login root ;;
		loginuser|27)			auto_login user ;;
		custom|30)				custom_install ;;
		setup|31)				setup_menu ;;
		copy|32)					clone_menu ;;
		setup|33)      		aur_package_install ;; 
		packages|34)			install_group ;;
		benchmark|35)			benchmark ;;
		'')						;;
		*)							echo -e "\nInvalid option ($choice)!\n"; ;;
	esac

	sync_disk
	disk_info

done


