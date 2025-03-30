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
	bcachefs subvolume snapshot -r / "$snapshot_dir/$snapshot" && echo -e "\nSaved!"

	ls $snapshot_dir --full-time | awk '{ print $6" @ "$7" - "$9}'

	sleep 1

	exit

fi

# Rest of script only deals with btrfs
[ ! $fstype = 'btrfs' ] && exit


case $description in
	1-min-auto)		saveLast=3; [ $(date +%M | sed 's/^[0-9]//') = '0' ] || [ $(date +%M | sed 's/^[0-9]//') = '5' ] && exit ;;
	5-min-auto)		saveLast=2; [ $(date +%M | sed 's/^[0-9]//') = '0' ] && exit ;;
	10-min-auto)	saveLast=2; [ $(date +%M) = '00' ] || [ $(date +%M) = '30' ] && exit ;;
	30-min-auto)	saveLast=2; [ $(date +%M) = '00' ] && exit ;;
	1-hr-auto)		saveLast=12; [ $(date +%H) = '00' ] && exit ;;
	1-day_auto)		saveLast=14 ;;
	quick-shot)		saveLast=3 ;;
	*)					saveLast=10; cleanup='' ;;
esac


#for snapshot in $(ls -t); do
for snapshot in * ; do
		
	if [ "$(echo -e "$snapshot" | grep quick-shot)" ]; then
	
			tobeDeleted="$tobeDeleted\n$snapshot"
			#tobeDeleted="$tobeDeleted $snapshot"
	fi

done

echo -e "$tobeDeleted"


#for i in $(echo -e ${tobeDeleted[@]} | tail -n +$(( saveLast + 2 ))); do
for i in ${tobeDeleted[@]}; do

	echo "Deleting snapshot #$i..."
	#rm -rf "$snapshot_dir/$i"	
done
ls $snapshot_dir


if [ $read_write = 'true' ]; then
	snapper -c root create -c "$cleanup" --read-write --description "$description"
else
	snapper -c root create -c "$cleanup" --description "$description"
fi


for snapshot in $(ls -t); do
	
	if [ $(grep "description>$description" /.snapshots/$snapshot/info.xml) ] && [ $(grep "cleanup>$cleanup" /.snapshots/$snapshot/info.xml) ]; then
	
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


if [ "$description" = "quick-shot" ]; then
	
	echo
	snapper list --columns number,date,cleanup,description,read-only

	echo -e "\nPress any key to continue.\n"; read -s -n1 -t 30 

fi


