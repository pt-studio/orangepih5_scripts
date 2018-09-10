#!/bin/bash
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
# Copyright (c) 2018 PT Studio
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is contain some part of the Armbian build script
# https://github.com/armbian/build/

# Main program
#

if [[ $(basename $0) == main.sh ]]; then
	echo "Please use main.sh as a symlink from parent folder to start the build process"
	echo "ln -s ../build.sh script/main.sh"
	exit -1
fi

# default umask for root is 022 so parent directories won't be group writeable without this
# this is used instead of making the chmod in prepare_host() recursive
umask 002

SRC="$(dirname "$(realpath "${BASH_SOURCE}")")"
SRC="$(dirname "$SRC")"

# check for whitespace in $SRC and exit for safety reasons
grep -q "[[:space:]]" <<<"${SRC}" && { echo "\"${SRC}\" contains whitespace. Not supported. Aborting." >&2 ; exit 1 ; }

cd $SRC
echo $SRC
# destination
DEST=$SRC/output

# if language not set, set to english
[[ -z $LANGUAGE ]] && export LANGUAGE="en_US:en"

# default console if not set
[[ -z $CONSOLE_CHAR ]] && export CONSOLE_CHAR="UTF-8"

# Load libraries
source $SRC/scripts/common.sh
source $SRC/scripts/image-helpers.sh
source $SRC/scripts/distributions-helpers.sh
source $SRC/scripts/desktop-helpers.sh
source $SRC/scripts/compile_uboot.sh
source $SRC/scripts/compile_kernel.sh
source $SRC/scripts/build_rootfs.sh
source $SRC/scripts/build_packages.sh
source $SRC/scripts/build_image.sh

# 
CCACHE=ccache
export PATH="/usr/lib/ccache:$PATH"
export CCACHE_DIR=${CCACHE_DIR:-$SRC/.ccache}

#
echo $PATH | grep sbin || export PATH=$PATH:/sbin:/usr/local/sbin:/usr/sbin
export PATH=$SRC/toolchain/gcc-linaro-aarch/bin:$PATH
export PATH=$SRC/toolchain/gcc-linaro/bin:$PATH

# Check and install dependencies, directory structure and settings
prepare_host

export CORES=$((`cat /proc/cpuinfo | grep processor | wc -l` + 1))
export UBOOT_TOOLCHAIN="ccache arm-linux-gnueabi-"
export LINUX_TOOLCHAIN="ccache aarch64-linux-gnu-"
export EXTERNAL_PATH="$SRC/external"
export OUTPUT_PATH="$SRC/output"

#MENUSTR="Welcome to OrangePi Build System. Pls choose your target hardware."
##########################################
# OPTION=$(whiptail --title "OrangePi Build System" \
	# --menu "$MENUSTR" 10 60 3 --cancel-button Exit --ok-button Select \
	# "0"  "OrangePi PC2" \
	# "1"  "OrangePi Prima(internal version)" \
	# "2"  "OrangePi Zero Plus2" \
	# 3>&1 1>&2 2>&3)

# if [ $OPTION = "0" ]; then
	# BOARD="OrangePiH5_PC2"
# elif [ $OPTION = "1" ]; then
	# BOARD="OrangePiH5_Prima"
# elif [ $OPTION = "2" ]; then
	# BOARD="OrangePiH5_Zero_Plus2"
# else
	# echo -e "\e[1;31m Pls select correct platform \e[0m"
	# exit 0
# fi

# MENUSTR="Distro Options"
# OPTION=$(whiptail --title "OrangePi Build System" \
	# --menu "$MENUSTR" 20 60 5 --cancel-button Finish --ok-button Select \
	# "0"   "Ubuntu Xenial" \
	# "1"   "Ubuntu Bionic 18.04" \

	# 3>&1 1>&2 2>&3)
# Build rootfs
# if [ $OPTION = "0" ]; then
	# RELEASE="xenial"
# elif [ $OPTION = "1" ]; then
	# RELEASE="bionic"
# fi

BOARD="OrangePiH5_Zero_Plus2"
RELEASE="xenial"

source $SRC/scripts/configuration.sh

cd $SRC/scripts
./change_flatform.sh $BOARD
cd -

# -------------------------------------------------------------------------------------------------

MENUSTR="Pls select build option"
OPTION=$(whiptail --title "OrangePI building script" \
	--menu "$MENUSTR" 20 60 12 --cancel-button Finish --ok-button Select \
	"0"   "Build Release Image" \
	"1"   "Build Rootfs" \
	"2"   "Build Uboot" \
	"3"   "Build Linux" \
	"4"   "Build Kernel only" \
	"5"   "Build Module only" \
	"6"   "Build Board Support Packages" \
	"99"  "Clean All" \
	"100" "Dev Area" \
	3>&1 1>&2 2>&3)

if [ $OPTION = "0" -o $OPTION = "1" ]; then
	echo ""
	# Compile uboot
	if [ ! -f $SRC/output/boot/uboot.bin -o ! -f $SRC/output/boot/boot0.bin ]; then
	    compile_uboot
	fi

	# Compile kernel uImage
	if [ ! -f $SRC/output/boot/orangepi/uImage ]; then
		compile_kernel
	fi

	# Compile kernel module .ko
	if [ ! -d $SRC/output/lib ]; then
		if [ -f $SRC/output/lib ]; then
			rm -f $SRC/output/lib
		fi

		compile_kernel_modules
	fi

	cd $SCRIPTS

	# Build rootfs
	if [ -d $SDCARD ]; then
		if (whiptail --title "OrangePi Build System" --yesno \
			"${RELEASE} rootfs has exist! Do you want use it?" 10 60) then
			echo ""
		else
			build_rootfs
		fi

	else
		build_rootfs
	fi

	# Package rootfs
	if [ $OPTION = "0" ]; then
		build_image
	fi

	exit 0

elif [ $OPTION = "2" ]; then
	compile_uboot
	exit 0
elif [ $OPTION = "3" ]; then
	build_kernel
	exit 0
elif [ $OPTION = "4" ]; then
	compile_kernel
	exit 0
elif [ $OPTION = "5" ]; then
	compile_kernel_modules
	exit 0
elif [ $OPTION = "6" ]; then
	#create_chroot $OUTPUT_PATH/buildroot xenial arm64
	chroot_build_packages $OUTPUT_PATH/buildroot
	exit 0
elif [ $OPTION = "99" ]; then
	display_alert "Cleaning build output" "$BOARD" "info"
	clean_uboot
	clean_kernel
	exit 0
elif [ $OPTION = "100" ]; then
	umount_chroot "$SDCARD"
	debootstrap_ng
	exit 0
else
	whiptail --title "OrangePi Build System" \
		--msgbox "Pls select correct option" 10 50 0
	exit 0
fi

