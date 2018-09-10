#!/bin/bash
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
# Copyright (c) 2018 PT Studio
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is contain some part of the Armbian build script
# https://github.com/armbian/build/

# common options
NORMAL_USER_NAME="orangepi"
NORMAL_USER_PASSWD="4321"
ROOTPWD="1234" # Must be changed @first login
HOST="orangepi" # set hostname to the board
#TZDATA=`cat /etc/timezone` # Timezone for target is taken from host or defined here.
TZDATA="Asia/Ho_Chi_Minh"
SERIALCON=ttyS0

#APT_PROXY_ADDR=172.16.234.23:3142
ARCH=arm64
QEMU_BINARY="qemu-aarch64-static"
BUILD_DESKTOP=yes
DEST_LANG="en_US.UTF-8"
MODULES="drm mali ump bcmdhd vfe_v4l2"


[[ -z $LANGUAGE ]] && export LANGUAGE="en_US:en"

# default console if not set
[[ -z $CONSOLE_CHAR ]] && export CONSOLE_CHAR="UTF-8"

ROOTFS_CACHE_MAX=16

# Base system dependencies
DEBOOTSTRAP_LIST="locales,gnupg,ifupdown"
[[ $BUILD_DESKTOP == yes ]] && DEBOOTSTRAP_LIST="locales,gnupg,ifupdown,libgtk2.0-bin"

# set unique mounting directory
SDCARD="$SRC/output/tmp/rootfs-${BOARD}-${RELEASE}-${BUILD_DESKTOP}"

KERNEL_COMPILER="aarch64-linux-gnu-"
UBOOT_COMPILER="arm-linux-gnueabihf"

# Essential packages
PACKAGE_LIST="bc bridge-utils build-essential cpufrequtils device-tree-compiler figlet fbset fping \
	iw fake-hwclock wpasupplicant psmisc ntp parted rsync sudo curl linux-base dialog crda \
	wireless-regdb ncurses-term python3-apt sysfsutils toilet u-boot-tools unattended-upgrades \
	usbutils wireless-tools console-setup unicode-data openssh-server initramfs-tools \
	ca-certificates resolvconf expect iptables automake \
	bison flex libwrap0-dev libssl-dev libnl-3-dev libnl-genl-3-dev"


# Non-essential packages
PACKAGE_LIST_ADDITIONAL="alsa-utils btrfs-tools dosfstools iotop iozone3 stress sysbench screen \
	ntfs-3g vim pciutils evtest htop nmon pv lsof apt-transport-https libfuse2 libdigest-sha-perl \
	libproc-processtable-perl aptitude dnsutils f3 haveged hdparm rfkill vlan sysstat bash-completion \
	hostapd git ethtool network-manager unzip ifenslave command-not-found libpam-systemd iperf3 \
	software-properties-common libnss-myhostname f2fs-tools avahi-autoipd iputils-arping qrencode"


# Dependent desktop packages
PACKAGE_LIST_DESKTOP="xorg nodm"


# Recommended desktop packages
PACKAGE_LIST_DESKTOP_RECOMMENDS="mplayer"


# Release specific packages
case $RELEASE in

	xenial)
		PACKAGE_LIST_RELEASE="man-db wget nano curl xz-utils iw rfkill"
		PACKAGE_LIST_DESKTOP+=" "
		PACKAGE_LIST_DESKTOP_RECOMMENDS+=" "
	;;

esac

UBUNTU_MIRROR='ports.ubuntu.com/'

# Build final package list after possible override
PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_RELEASE $PACKAGE_LIST_ADDITIONAL"

[[ $BUILD_DESKTOP == yes ]] && PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_DESKTOP $PACKAGE_LIST_DESKTOP_RECOMMENDS"

[[ -n $APT_PROXY_ADDR ]] && display_alert "Using custom apt-cacher-ng address" "$APT_PROXY_ADDR" "info"

