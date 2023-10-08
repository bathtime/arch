#!/bin/bash

cd /home/user


FILES="
.config/kded5rc
.config/kglobalshortcutsrc
.config/konsolerc
.config/kscreenlockerrc
.config/ksmserverrc
.config/kwinrulesrc
.config/plasma-org.kde.plasma.desktop-appletsrc
.config/plasmashellrc
.local/share/konsole/*.profile
.local/share/kxmlgui5/konsole/konsoleui.rc
.local/share/kxmlgui5/konsole/sessionui.rc
.local/share/plasma/plasmoids/*
.local/share/user-places.xbel
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
