# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
# Copyright (c) 2018 PT Studio
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is contain some part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# install_common
# install_distribution_specific
# post_debootstrap_tweaks

install_common()
{
	display_alert "Applying common tweaks" "" "info"

	# define ARCH within global environment variables
	[[ -f $SDCARD/etc/environment ]] && echo "ARCH=${ARCH//hf}" >> $SDCARD/etc/environment

	# add dummy fstab entry to make mkinitramfs happy
	cat <<- EOF > $SDCARD/etc/fstab
	/dev/mmcblk0p2 /boot vfat defaults 1 2
	/dev/mmcblk0p1 /     ext4 defaults 1 1
	EOF

	# create modules file
	tr ' ' '\n' <<< "$MODULES" > $SDCARD/etc/modules

	# create blacklist files
	# TODO

	# remove default interfaces file if present
	# before installing board support package
	rm -f $SDCARD/etc/network/interfaces

	mkdir -p $SDCARD/selinux

	# remove Ubuntu's legal text
	[[ -f $SDCARD/etc/legal ]] && rm $SDCARD/etc/legal

	# Prevent loading paralel printer port drivers which we don't need here.Suppress boot error if kernel modules are absent
	if [[ -f $SDCARD/etc/modules-load.d/cups-filters.conf ]]; then
		sed "s/^lp/#lp/" -i $SDCARD/etc/modules-load.d/cups-filters.conf
		sed "s/^ppdev/#ppdev/" -i $SDCARD/etc/modules-load.d/cups-filters.conf
		sed "s/^parport_pc/#parport_pc/" -i $SDCARD/etc/modules-load.d/cups-filters.conf
	fi

	# console fix due to Debian bug
	sed -e 's/CHARMAP=".*"/CHARMAP="'$CONSOLE_CHAR'"/g' -i $SDCARD/etc/default/console-setup

	# change time zone data
	echo $TZDATA > $SDCARD/etc/timezone
	chroot $SDCARD /bin/bash -c "dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1"

	# add normal user
	chroot $SDCARD /bin/bash -c "adduser --gecos $NORMAL_USER_NAME --disabled-login $NORMAL_USER_NAME --uid 1000"
	chroot $SDCARD /bin/bash -c "(echo $NORMAL_USER_PASSWD;echo $NORMAL_USER_PASSWD;) | passwd $NORMAL_USER_NAME"
	chroot $SDCARD /bin/bash -c "usermod -a -G sudo,adm,input,video,plugdev $NORMAL_USER_NAME"

	# set root password
	chroot $SDCARD /bin/bash -c "(echo $ROOTPWD;echo $ROOTPWD;) | passwd root >/dev/null 2>&1"
	# force change root password at first login
	chroot $SDCARD /bin/bash -c "chage -d 0 root"

	# display welcome message at first root login
	touch $SDCARD/root/.not_logged_in_yet
	
	# initial date for fake-hwclock
	date -u '+%Y-%m-%d %H:%M:%S' > $SDCARD/etc/fake-hwclock.data

	echo $HOST > $SDCARD/etc/hostname

	# set hostname in hosts file
	cat <<-EOF > $SDCARD/etc/hosts
	127.0.0.1   localhost $HOST
	::1         localhost $HOST ip6-localhost ip6-loopback
	fe00::0     ip6-localnet
	ff00::0     ip6-mcastprefix
	ff02::1     ip6-allnodes
	ff02::2     ip6-allrouters
	EOF

	if [[ $BUILD_DESKTOP == yes ]]; then
		# install display manager
		desktop_postinstall
	fi

	# Cosmetic fix [FAILED] Failed to start Set console font and keymap at first boot
	[[ -f $SDCARD/etc/console-setup/cached_setup_font.sh ]] && sed -i "s/^printf '.*/printf '\\\033\%\%G'/g" $SDCARD/etc/console-setup/cached_setup_font.sh
	[[ -f $SDCARD/etc/console-setup/cached_setup_terminal.sh ]] && sed -i "s/^printf '.*/printf '\\\033\%\%G'/g" $SDCARD/etc/console-setup/cached_setup_terminal.sh
	[[ -f $SDCARD/etc/console-setup/cached_setup_keyboard.sh ]] && sed -i "s/-u/-x'/g" $SDCARD/etc/console-setup/cached_setup_keyboard.sh

	# disable repeated messages due to xconsole not being installed.
	[[ -f $SDCARD/etc/rsyslog.d/50-default.conf ]] && sed '/daemon\.\*\;mail.*/,/xconsole/ s/.*/#&/' -i $SDCARD/etc/rsyslog.d/50-default.conf
	# disable deprecated parameter
	sed '/.*$KLogPermitNonKernelFacility.*/,// s/.*/#&/' -i $SDCARD/etc/rsyslog.conf

	# enable getty on serial console
	chroot $SDCARD /bin/bash -c "systemctl --no-reload enable serial-getty@$SERIALCON.service >/dev/null 2>&1"

	# install initial asound.state if defined
	mkdir -p $SDCARD/var/lib/alsa/
	cp -f $SRC/external/blobs/asound.state $SDCARD/var/lib/alsa/asound.state

	# Copy overlay
	rsync -avzq --chown=root:root $SRC/external/blobs/bsp/ $SDCARD/

	chroot $SDCARD /bin/systemctl enable cpu-corekeeper
	chroot $SDCARD /bin/systemctl enable ssh-keygen

	# DNS fix. package resolvconf is not available everywhere
	if [ -d /etc/resolvconf/resolv.conf.d ]; then
		echo -e "# In case of DNS problems, try uncommenting this and reboot for debugging\n# nameserver 1.1.1.1" \
		> $SDCARD/etc/resolvconf/resolv.conf.d/head
	fi

	# premit root login via SSH for the first boot
	sed -i 's/#\?PermitRootLogin .*/PermitRootLogin yes/' $SDCARD/etc/ssh/sshd_config

	# enable PubkeyAuthentication. Enabled by default everywhere except on Jessie
	sed -i 's/#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' $SDCARD/etc/ssh/sshd_config

	# configure network manager
	sed "s/managed=\(.*\)/managed=true/g" -i $SDCARD/etc/NetworkManager/NetworkManager.conf

}

install_distribution_specific()
{
	display_alert "Applying distribution specific tweaks for" "$RELEASE" "info"
	case $RELEASE in
	xenial)
		# remove legal info from Ubuntu
		[[ -f $SDCARD/etc/legal ]] && rm $SDCARD/etc/legal

		# disable not working on unneeded services
		# ureadahead needs kernel tracing options that AFAIK are present only in mainline
		chroot $SDCARD /bin/bash -c "systemctl --no-reload mask ondemand.service ureadahead.service setserial.service etc-setserial.service >/dev/null 2>&1"
		;;
	esac
}

post_debootstrap_tweaks()
{
	# remove service start blockers and QEMU binary
	rm -f $SDCARD/sbin/initctl $SDCARD/sbin/start-stop-daemon
	chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --remove /sbin/initctl"
	chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --remove /sbin/start-stop-daemon"

	chroot $SDCARD /bin/bash -c 'echo "resolvconf resolvconf/linkify-resolvconf boolean true" | debconf-set-selections'
	mkdir -p $SDCARD/var/lib/resolvconf/
	:> $SDCARD/var/lib/resolvconf/linkified

	rm -f $SDCARD/usr/sbin/policy-rc.d $SDCARD/usr/bin/$QEMU_BINARY

	# reenable resolvconf managed resolv.conf
	ln -sf /run/resolvconf/resolv.conf $SDCARD/etc/resolv.conf
}
