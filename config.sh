#!/bin/bash

cd /home/user


FILES="

.config/kded5rc
.local/share/konsole/*.profile
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
    #rm "$FILE"
done



tar cvf setup.tar $FILES

exit

#gpg -c setup.tar

tar xvzf setup.tar
