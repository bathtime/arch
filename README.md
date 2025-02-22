# arch
A script to install Arch linux on a USB stick

To run from an arch iso:

nmcli radio wifi on
nmcli device wifi connect <WIFI-SSID> password <WIFI-PASSWORD>
curl -sL bit.ly/a-install > arch.sh
chmod +x arch.sh
./arch.sh

Run on the fly: bash <(curl -sL bit.ly/a-install)

Supported filesystems: ext4, btrfs, xfs, f2fs, bcachefs

**Features**

- Ability to clone drive to USB
- bcachefs rsync allows for complete rollback of root drive (not fully tested. use are your own risk!)


**BUGS:**

1. encrypted bcachefs throws an error after entering password twice when prompted during boot. Login succeeds nonetheless.
2. bcachefs cannot install an ext4 system due to some known bug in bcachefs. You may install btrfs or bcachefs instead.
3. 


