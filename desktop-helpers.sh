# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
# Copyright (c) 2018 PT Studio
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is contain some part of the Armbian build script
# https://github.com/armbian/build/

desktop_postinstall ()
{
	# stage: install display manager
	display_alert "Installing" "display manager: nodm" "info"
	
	cat <<- EOF > "$SDCARD/etc/X11/xorg.conf"
	Section "Device"
		Identifier      "Allwinner H5 FBDEV"
		Driver          "fbturbo"
		Option          "fbdev" "/dev/fb0"

		Option          "SwapbuffersWait" "true"
	EndSection
	EOF
	
	sed -i "s/NODM_USER=\(.*\)/NODM_USER=${NORMAL_USER_NAME}/" $SDCARD/etc/default/nodm
	sed -i "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=true/g" $SDCARD/etc/default/nodm

	display_alert "Installing support library" "Mali 450 r5p001rel0" "info"
	rsync -avz --chown root:root $SRC/cache/mali450-r5p001rel0/ $SDCARD/usr/lib/
}
