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

error_check 0


ucode=intel-ucode
aurApp=paru

user=user
hostname=Arch
password=123456

wifi_ssid="BELL364"
wifi_pass="13FDC4A93E3C"


# Post setup

post_install_apps="plasma-desktop plasma-wayland-session plasma-pa kscreen dolphin konsole firefox"
autostartapp="startplasma-wayland"


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

	pacman -S "$post_install_apps"

	echo 'if [[ ! "${DISPLAY}" && "${XDG_VTNR}" == 1 ]]; then
  	#autostartapp
fi' >> /home/$user/.bash_profile

	sed -i "s/#autostartapp/$autostartapp/" /home/$user/bash_profile

}


clean_system () {

	echo "Cleaning system..."

	rm -rf /home/user/.cache/mozilla/

	cd /home/$user/.mozilla/firefox
	rm -rf 'Crash Reports' 'Pending Pings'


	profile=$(ls /home/user/.mozilla/firefox/ | grep .*.default-release)
	cd $profile

	rm -rf crashes cookies.sqlite* minidumps datareporting sessionstore-backups saved-telemetry-pings storage weave* browser-extension-data security_state gmp-gmpopenh264 synced-tabs.db-wal places.sqlite favicons.sqlite cert9.db places.sqlite-wal storage-sync-v2.sqlite-wal webappsstore.sqlite
	#rm -rf crashes cookies.sqlite* minidumps datareporting sessionstore-backups saved-telemetry-pings storage weave* browser-extension-data security_state gmp-gmpopenh264 synced-tabs.db-wal places.sqlite favicons.sqlite cert9.db

}


backup_config () {


	clean_system

	sleep 1

	cd /home/$user

	sudo -u $user tar -pcvf setup.tar $CONFIG_FILES

	ls -lah setup.tar
	#gpg -c setup.tar

}

restore_config () {

	cd /home/$user

	sudo -u $user tar xvf setup.tar

}



download_script () {

	echo -e "\nDowloading script from Github..."

	curl -sL https://raw.githubusercontent.com/bathtime/arch/main/post.sh > arch.sh

	if [[ "$?" -eq 0 ]]; then
   	echo "Download successful!"
 		chmod +x post.sh
	else
   	echo "Download unsuccessful."
	fi

}



last_modified () {

	cd /home/$user
	find . -cmin -1 -printf '%t %p\n' | sort -k 1 -n | cut -d' ' -f2-

}

CONFIG_FILES=".config/baloofilerc
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
.viminfo
.mozilla/*"



choices=("1. Quit
2. Backup config
3. Restore config
4. Post setup
5. Download script
6. Connect wireless
7. Cleanup system
8. Last modified")

while :; do

echo
echo "${choices[@]}" | column
echo  

read -p "Which option? " choice

	case $choice in
		quit|q|exit|1)	echo "Quitting!"; break; ;;
		backup|2)		backup_config ;;
		restore|3)		restore_config ;;	
		post|4)			post_setup ;;
		download|5)		download_script ;;
		connect|6)		connect_wireless ;;
		clean|7)			clean_system ;;
		last|8)			last_modified ;;
		'')				last_modified ;;
		*)             echo -e "\nInvalid option ($choice)!\n" ;;
 	esac
done


