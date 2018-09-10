# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
# Copyright (c) 2018 PT Studio
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is contain some part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# mount_chroot
# umount_chroot
# unmount_on_exit
# check_loop_device
# install_external_applications
# install_deb_chroot


# mount_chroot <target>
#
# helper to reduce code duplication
#
mount_chroot()
{
	local target=$1
	mount -t proc chproc $target/proc
	mount -t sysfs chsys $target/sys
	mount -t devtmpfs chdev $target/dev || mount --bind /dev $target/dev
	mount -t devpts chpts $target/dev/pts
}

# umount_chroot <target>
#
# helper to reduce code duplication
#
umount_chroot()
{
	local target=$1
	umount -l $target/dev/pts >/dev/null 2>&1 || true
	umount -l $target/dev >/dev/null 2>&1 || true
	umount -l $target/proc >/dev/null 2>&1 || true
	umount -l $target/sys >/dev/null 2>&1 || true
}

# unmount_on_exit
#
unmount_on_exit()
{
	trap - INT TERM EXIT
	umount_chroot "$SDCARD/"
	umount -l $SDCARD/tmp >/dev/null 2>&1
	umount -l $SDCARD >/dev/null 2>&1
	umount -l $MOUNT/boot >/dev/null 2>&1
	umount -l $MOUNT >/dev/null 2>&1
	losetup -d $LOOP >/dev/null 2>&1
	rm -rf --one-file-system $SDCARD
	exit_with_error "debootstrap-ng was interrupted"
}

# check_loop_device <device_node>
#
check_loop_device()
{
	local device=$1
	if [[ ! -b $device ]]; then
		if [[ $CONTAINER_COMPAT == yes && -b /tmp/$device ]]; then
			display_alert "Creating device node" "$device"
			mknod -m0660 $device b 0x$(stat -c '%t' "/tmp/$device") 0x$(stat -c '%T' "/tmp/$device")
		else
			exit_with_error "Device node $device does not exist"
		fi
	fi
}

install_external_applications()
{
	display_alert "Installing extra applications and drivers" "" "info"

	for plugin in $SRC/packages/extras/*.sh; do
		source $plugin
	done
}

install_deb_chroot()
{
	local package=$1
	local name=$(basename $package)
	cp $package $SDCARD/root/$name
	display_alert "Installing" "$name"
	chroot $SDCARD /bin/bash -c "dpkg -i /root/$name" >> $DEST/debug/install.log 2>&1
	rm -f $SDCARD/root/$name
}
