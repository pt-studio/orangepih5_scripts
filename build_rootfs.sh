# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
# Copyright (c) 2018 PT Studio
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is contain some part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# create_rootfs_cache
# debootstrap_ng

create_rootfs_cache()
{
	local packages_hash="20180906"
	local cache_fname=$SRC/cache/rootfs/${RELEASE}-ng-$ARCH.$packages_hash.tar.lz4
	local display_name=${RELEASE}-ng-$ARCH.${packages_hash}.tar.lz4

	if [[ -f $cache_fname ]]; then
		local date_diff=$(( ($(date +%s) - $(stat -c %Y $cache_fname)) / 86400 ))
		display_alert "Extracting $display_name" "$date_diff days old" "info"
		pv -p -b -r -c -N "$display_name" "$cache_fname" | lz4 -dc | tar xp --xattrs -C $SDCARD/
	else
		display_alert "Creating new rootfs for" "$RELEASE" "info"

		# apt-cacher-ng apt-get proxy parameter
		local apt_extra="-o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\""
		local apt_mirror="http://${APT_PROXY_ADDR:-localhost:3142}/$UBUNTU_MIRROR"

		# fancy progress bars
		[[ -z $OUTPUT_DIALOG ]] && local apt_extra_progress="--show-progress -o DPKG::Progress-Fancy=1"

		display_alert "Installing base system" "Stage 1/2" "info"
		eval 'debootstrap --include=${DEBOOTSTRAP_LIST} \
			--arch=$ARCH \
			--foreign $RELEASE \
			$SDCARD/ $apt_mirror' \
			| tee -a $DEST/debootstrap.log

		[[ ${PIPESTATUS[0]} -ne 0 || ! -f $SDCARD/debootstrap/debootstrap ]] && exit_with_error "Debootstrap base system first stage failed"

		cp /usr/bin/$QEMU_BINARY $SDCARD/usr/bin/

		mkdir -p $SDCARD/usr/share/keyrings/
		cp /usr/share/keyrings/debian-archive-keyring.gpg $SDCARD/usr/share/keyrings/
		cp /usr/share/keyrings/ubuntu-archive-keyring.gpg $SDCARD/usr/share/keyrings/

		display_alert "Installing base system" "Stage 2/2" "info"
		eval 'chroot $SDCARD /bin/bash -c "/debootstrap/debootstrap --second-stage"' \
			| tee -a $DEST/debootstrap.log

		[[ ${PIPESTATUS[0]} -ne 0 || ! -f $SDCARD/bin/bash ]] && exit_with_error "Debootstrap base system second stage failed"

		mount_chroot "$SDCARD"

		# policy-rc.d script prevents starting or reloading services during image creation
		printf '#!/bin/sh\nexit 101' > $SDCARD/usr/sbin/policy-rc.d
		chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/initctl"
		chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/start-stop-daemon"
		printf '#!/bin/sh\necho "Warning: Fake start-stop-daemon called, doing nothing"' > $SDCARD/sbin/start-stop-daemon
		printf '#!/bin/sh\necho "Warning: Fake initctl called, doing nothing"' > $SDCARD/sbin/initctl
		chmod 755 $SDCARD/usr/sbin/policy-rc.d
		chmod 755 $SDCARD/sbin/initctl
		chmod 755 $SDCARD/sbin/start-stop-daemon

		# stage: configure language and locales
		display_alert "Configuring locales" "$DEST_LANG" "info"

		[[ -f $SDCARD/etc/locale.gen ]] && sed -i "s/^# $DEST_LANG/$DEST_LANG/" $SDCARD/etc/locale.gen
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "locale-gen $DEST_LANG"'
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=$DEST_LANG"'

		if [[ -f $SDCARD/etc/default/console-setup ]]; then
			sed -e 's/CHARMAP=.*/CHARMAP="UTF-8"/' -e 's/FONTSIZE=.*/FONTSIZE="8x16"/' \
				-e 's/CODESET=.*/CODESET="guess"/' -i $SDCARD/etc/default/console-setup
			eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "setupcon --save"'
		fi

		# stage: create apt sources list
		create_sources_list "$RELEASE" "$SDCARD/"

		# compressing packages list to gain some space
		echo "Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";" > $SDCARD/etc/apt/apt.conf.d/02compress-indexes
		echo "Acquire::Languages "none";" > $SDCARD/etc/apt/apt.conf.d/no-languages

		# add armhf arhitecture to arm64
		[[ $ARCH == arm64 ]] && eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "dpkg --add-architecture armhf"'

		# this should fix resolvconf installation failure in some cases
		chroot $SDCARD /bin/bash -c 'echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections'

		# stage: update packages list
		display_alert "Updating package list" "$RELEASE" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "apt-get -q -y $apt_extra update"' \
			| tee -a $DEST/debootstrap.log

		#[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Updating package lists failed"

		# stage: upgrade base packages from xxx-updates and xxx-backports repository branches
		display_alert "Upgrading base packages" "$RELEASE" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress upgrade"' \
			| tee -a $DEST/debootstrap.log

		#[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Upgrading base packages failed"

		# stage: install additional packages
		display_alert "Installing packages for" "$RELEASE" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress --no-install-recommends install $PACKAGE_LIST"' \
			| tee -a $DEST/debootstrap.log

		[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Installation of additional packages failed"

		# DEBUG: print free space
		echo -e "\nFree space:"
		eval 'df -h' | tee -a $DEST/debootstrap.log

		# stage: remove downloaded packages
		chroot $SDCARD /bin/bash -c "apt-get clean"

		# this is needed for the build process later since resolvconf generated file in /run is not saved
		rm $SDCARD/etc/resolv.conf
		echo 'nameserver 1.1.1.1' >> $SDCARD/etc/resolv.conf

		# stage: make rootfs cache archive
		display_alert "Ending debootstrap process and preparing cache" "$RELEASE" "info"
		sync
		# the only reason to unmount here is compression progress display
		# based on rootfs size calculation
		umount_chroot "$SDCARD"

		tar cp --xattrs \
			--directory=$SDCARD/ \
			--exclude='./dev/*' \
			--exclude='./proc/*' \
			--exclude='./run/*' \
			--exclude='./tmp/*' \
			--exclude='./sys/*' . | pv -p -b -r -s $(du -sb $SDCARD/ | cut -f1) -N "$display_name" | lz4 -c > $cache_fname

	fi

	mount_chroot "$SDCARD"
}

debootstrap_ng() {
	display_alert "Starting rootfs and image building process for" "$BOARD $RELEASE" "info"

	# trap to unmount stuff in case of error/manual interruption
	trap unmount_on_exit INT TERM EXIT

	# stage: clean and create directories
	rm -rf $SDCARD $MOUNT
	mkdir -p $SDCARD $MOUNT $SRC/cache/rootfs

	# stage: verify tmpfs configuration and mount
	# default maximum size for tmpfs mount is 1/2 of available RAM
	# CLI needs ~1.2GiB+ (Xenial CLI), Desktop - ~2.8GiB+ (Xenial Desktop w/o HW acceleration)
	# calculate and set tmpfs mount to use 2/3 of available RAM
	local phymem=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 * 2 / 3 )) # MiB
	if [[ $BUILD_DESKTOP == yes ]]; then local tmpfs_max_size=3500; else local tmpfs_max_size=1500; fi # MiB
	if [[ $FORCE_USE_RAMDISK == no ]]; then	local use_tmpfs=no
	elif [[ $FORCE_USE_RAMDISK == yes || $phymem -gt $tmpfs_max_size ]]; then
		local use_tmpfs=yes
	fi
	[[ -n $FORCE_TMPFS_SIZE ]] && phymem=$FORCE_TMPFS_SIZE

	[[ $use_tmpfs == yes ]] && mount -t tmpfs -o size=${phymem}M tmpfs $SDCARD

	# stage: prepare basic rootfs: unpack cache or create from scratch
	create_rootfs_cache

	# install distribution and board specific applications
	display_alert "Install distribution specific" "target" "info"
	install_distribution_specific
	display_alert "Install common" "target" "info"
	install_common

	# Install kernel modules + firmware
	rm -rf $SDCARD/lib/modules
	mkdir -p "$SDCARD/lib/modules"

	display_alert "Install kernel modules and firmware" "target" "info"
	rsync -avzq --chown=root:root $OUTPUT_PATH/lib/ $SDCARD/lib/

	display_alert "Install custom blobs firmware" "target" "info"
	rsync -avzq --chown=root:root $EXTERNAL_PATH/firmware/ $SDCARD/lib/firmware/
	
	chroot_installpackages_local
	post_debootstrap_tweaks

	# clean up / prepare for making the image
	umount_chroot "$SDCARD"

	# stage: unmount tmpfs
	#[[ $use_tmpfs = yes ]] && umount $SDCARD
	#rm -rf $SDCARD

	# remove exit trap
	trap - INT TERM EXIT
	display_alert "Build rootfs done" "target" "info"
}

build_rootfs() {
	debootstrap_ng

}
