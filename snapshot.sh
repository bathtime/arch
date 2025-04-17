#!/bin/bash

description="$1"
cleanup=timeline
read_write=false
snapshot_dir=/.snapshots
fstype="$(mount | grep ' / ' | awk '{ print $5 }')"

cd $snapshot_dir

if [ "$fstype" = 'bcachefs' ]; then

	#ls $snapshot_dir
	ls -l --full-time | cut -d" " -f6- | cut -d' ' -f3 --complement | sed 's/\.[0-9]*/ -/'


	echo -e "\nPlease enter a name for the snapshot: \n"

	read snapshot
	bcachefs subvolume snapshot / "$snapshot_dir/$snapshot" && echo -e "\nSaved!"

	sleep 1

	echo "Syncing..."
	sync
	sleep 1

	echo -e "\nPress 'r' to reboot.\n"
	read -sN1 key

	[ $key = 'r' ] && reboot
	
	exit

fi


case $description in
	1-min-auto)		saveLast=3; [ $(date +%M | sed 's/^[0-9]//') = '0' ] || [ $(date +%M | sed 's/^[0-9]//') = '5' ] && exit ;;
	5-min-auto)		saveLast=2; [ $(date +%M | sed 's/^[0-9]//') = '0' ] && exit ;;
	10-min-auto)	saveLast=2; [ $(date +%M) = '00' ] || [ $(date +%M) = '30' ] && exit ;;
	30-min-auto)	saveLast=2; [ $(date +%M) = '00' ] && exit ;;
	1-hr-auto)		saveLast=12; [ $(date +%H) = '00' ] && exit ;;
	1-day_auto)		saveLast=14 ;;
	quick-shot)		saveLast=3 ;;
	'')				cleanup=''
						saveLast=100
						read_write=true
						snapper list --columns number,date,cleanup,description,read-only
						echo -e "\nWhat would you like to call this snapshot?\n"
						read description
						;;
	*)					saveLast=10; cleanup='' ;;
esac


#for snapshot in $(ls -t); do
for snapshot in * ; do
		
	if [ "$(echo -e "$snapshot" | grep quick-shot)" ]; then
	
			tobeDeleted="$tobeDeleted\n$snapshot"
	fi

done

#echo -e "$tobeDeleted"


for i in ${tobeDeleted[@]}; do

	echo "Deleting snapshot #$i..."
	#rm -rf "$snapshot_dir/$i"	
done


if [ $read_write = 'true' ]; then
	snapper -c root create -c "$cleanup" --read-write --description "$description"
else
	snapper -c root create -c "$cleanup" --description "$description"
fi

grub-mkconfig -o /boot/grub/grub.cfg


for snapshot in $(ls -t); do
	
	if [[ $(grep "description>$description" /.snapshots/$snapshot/info.xml) ]] && [ $(grep "cleanup>$cleanup" /.snapshots/$snapshot/info.xml) ]; then
	
		# Don't delete the current/active snapshot (marked with a '*')
		if [ ! "$(snapper list | grep -E '[0-9][*+-] ' | awk '{ print $1 }' | grep $snapshot)" ]; then
			tobeDeleted="$tobeDeleted\n$snapshot"
		fi
	fi

done

#echo -e "\nList of snapshots:\n$tobeDeleted"

for i in $(echo -e "$tobeDeleted" | tail -n +$(( saveLast + 2 ))); do

	echo "Deleting snapshot #$i..."
	snapper -c root delete --sync $i

done


#if [ "$description" = "quick-shot" ]; then
if [ "$cleanup" = "" ]; then
	
	echo
	snapper list --columns number,date,cleanup,description,read-only
	
#echo; ls $snapshot_dir

	echo -e "\nPress any key to continue.\n"; read -s -n1

fi


