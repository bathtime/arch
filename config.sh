#!/bin/bash

cd /home/user


FILES="
.local/share/kxmlgui5/konsole/konsoleui.rc
.config/kded5rc
.config/konsolerc
.local/share/konsole/*.profile
.config/plasmashellrc
.config/kwinrulesrc
.config/ksmserverrc
.config/plasma-org.kde.plasma.desktop-appletsrc
.local/share/kxmlgui5/konsole/sessionui.rc
.local/share/plasma/plasmoids/*
.mozilla/*

"

for FILE in $FILES
do
    ls -la "$FILE"
    rm -rf "$FILE"
done



#tar cvf setup.tar $FILES

exit

#gpg -c setup.tar

tar xvzf setup.tar
