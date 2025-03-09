# arch
A script to install Arch linux on a USB stick or machine.

This script was intended to be used for just myself, but all are welcome to use, edit, or share. Just don't expect any instructions.

**Running from an arch iso**

nmcli radio wifi on

nmcli device wifi connect WIFI-SSID password WIFI-PASSWORD

bash <(curl -sL bit.ly/a-install)

**Auto install**

1. Select disk to install to
2. Select 'Auto-install'
3. Choose a window manager


**Features**

- Ability to install and run Arch on USB
- All newly installed systems are able to install other systems
- Packages will be drawn from the host if they exist (saving on bandwidth and time)
- Create and clone from any one filesystem type to another (ext4, btrfs, xfs, bcachefs, f2fs, nilfs2, jfs)
- btrfs and bcachefs rsync allows for complete rollback of root drive
- Easily backup user/root configs to a compressed file
- Sets up wifi, passwords, auto-login, window manager, custom configs/files... automatically

**BUGS:**

1. encrypted bcachefs throws an error after entering password twice when prompted during boot. Login succeeds nonetheless.
2. Cloning a system from xfs to bcachefs or bcachefs to f2fs will only allow boot with booster initram (dracut and mkinitcpio will not boot)
3. Many more bugs, but who wants to hear about them? Lets talk about good things.


