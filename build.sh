#!/bin/bash
set -e
##########################################
##
## Build H5 Linux
## 
## Maintainer: Buddy <buddy.zhang@aliyun.com>
##########################################
export ROOT=`pwd`
SCRIPTS=$ROOT/scripts
export BOOT_PATH
export ROOTFS_PATH
export UBOOT_PATH

export PATH=/home/vagrant/armbian/cache/toolchains/gcc-linaro-4.9.4-2017.01-x86_64_aarch64-linux-gnu/bin:$PATH
export PATH=/home/vagrant/armbian/cache/toolchains/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabi/bin:$PATH

export UBOOT_TOOLCHAIN="ccache arm-linux-gnueabi-"
export LINUX_TOOLCHAIN="ccache aarch64-linux-gnu-"

root_check()
{
	if [ "$(id -u)" -ne "0" ]; then
		echo "This option requires root."
		echo "Pls use command: sudo ./build.sh"
		exit 0
	fi	
}

UBOOT_check()
{
	for ((i = 0; i < 5; i++)); do
		UBOOT_PATH=$(whiptail --title "OrangePi Build System" \
			--inputbox "Pls input device node of SDcard.(/dev/sdb)" \
			10 60 3>&1 1>&2 2>&3)
	
		if [ $i = "4" ]; then
			whiptail --title "OrangePi Build System" --msgbox "Error, Invalid Path" 10 40 0	
			exit 0
		fi


		if [ ! -b "$UBOOT_PATH" ]; then
			whiptail --title "OrangePi Build System" --msgbox \
				"The input path invalid! Pls input correct path!" \
				--ok-button Continue 10 40 0	
		else
			i=200 
		fi 
	done
}

BOOT_check()
{
	## Get mount path of u-disk
	for ((i = 0; i < 5; i++)); do
		BOOT_PATH=$(whiptail --title "OrangePi Build System" \
			--inputbox "Pls input mount path of BOOT.(/media/orangepi/BOOT)" \
			10 60 3>&1 1>&2 2>&3)
	
		if [ $i = "4" ]; then
			whiptail --title "OrangePi Build System" --msgbox "Error, Invalid Path" 10 40 0	
			exit 0
		fi


		if [ ! -d "$BOOT_PATH" ]; then
			whiptail --title "OrangePi Build System" --msgbox \
				"The input path invalid! Pls input correct path!" \
				--ok-button Continue 10 40 0	
		else
			i=200 
		fi 
	done
}

ROOTFS_check()
{
	for ((i = 0; i < 5; i++)); do
		ROOTFS_PATH=$(whiptail --title "OrangePi Build System" \
			--inputbox "Pls input mount path of rootfs.(/media/orangepi/rootfs)" \
			10 60 3>&1 1>&2 2>&3)
	
		if [ $i = "4" ]; then
			whiptail --title "OrangePi Build System" --msgbox "Error, Invalid Path" 10 40 0	
			exit 0
		fi


		if [ ! -d "$ROOTFS_PATH" ]; then
			whiptail --title "OrangePi Build System" --msgbox \
				"The input path invalid! Pls input correct path!" \
				--ok-button Continue 10 40 0	
		else
			i=200 
		fi 
	done
}

if [ ! -d $ROOT/output ]; then
    mkdir -p $ROOT/output
fi

MENUSTR="Welcome to OrangePi Build System. Pls choose Platform."
##########################################
# OPTION=$(whiptail --title "OrangePi Build System" \
	# --menu "$MENUSTR" 10 60 3 --cancel-button Exit --ok-button Select \
	# "0"  "OrangePi PC2" \
	# "1"  "OrangePi Prima(internal version)" \
	# "2"  "OrangePi Zero Plus2" \
	# 3>&1 1>&2 2>&3)

# if [ $OPTION = "0" ]; then
	# export PLATFORM="OrangePiH5_PC2"
# elif [ $OPTION = "1" ]; then
	# export PLATFORM="OrangePiH5_Prima"
# elif [ $OPTION = "2" ]; then
	# export PLATFORM="OrangePiH5_Zero_Plus2"
# else
	# echo -e "\e[1;31m Pls select correct platform \e[0m"
	# exit 0
# fi
export PLATFORM="OrangePiH5_Zero_Plus2"
cd $ROOT/scripts
./change_flatform.sh $PLATFORM
cd -

if [ ! -d $ROOT/output ]; then
    mkdir -p $ROOT/output
fi

MENUSTR="Pls select build option"

OPTION=$(whiptail --title "OrangePi Build System" \
	--menu "$MENUSTR" 20 60 12 --cancel-button Finish --ok-button Select \
	"0"   "Build Release Image" \
	"1"   "Build Rootfs" \
	"2"   "Build Uboot" \
	"3"   "Build Linux" \
	"4"   "Build Kernel only" \
	"5"   "Build Module only" \
	"6"   "Install Image into SDcard" \
	"7"   "Update kernel Image" \
	"8"   "Update Module" \
	"9"   "Update Uboot" \
	"10"  "Update SDK to Github" \
	"11"  "Update SDK from Github" \
	3>&1 1>&2 2>&3)

if [ $OPTION = "0" -o $OPTION = "1" ]; then
	sudo echo ""
	clear
	TMP=$OPTION
	TMP_DISTRO=""
	MENUSTR="Distro Options"
	# OPTION=$(whiptail --title "OrangePi Build System" \
		# --menu "$MENUSTR" 20 60 5 --cancel-button Finish --ok-button Select \
		# "0"   "ArchLinux" \
		# "1"   "Ubuntu Xenial" \
		# "2"   "Debian Jessie" \

		# 3>&1 1>&2 2>&3)
	OPTION=1

	# Compile uboot
	if [ ! -f $ROOT/output/uboot.bin -o ! -f $ROOT/output/boot0.bin ]; then
	    cd $SCRIPTS
		./uboot_compile.sh
		cd -
	fi

	# Compile kernel uImage
	if [ ! -f $ROOT/output/uImage ]; then
		export BUILD_KERNEL=1
		cd $SCRIPTS
		./kernel_compile.sh
		cd -
	fi

	# Compile kernel module .ko
	if [ ! -d $ROOT/output/lib ]; then
		if [ -f $ROOT/output/lib ]; then
			rm -f $ROOT/output/lib
		fi

		mkdir -p $ROOT/output/lib
		export BUILD_MODULE=1
		cd $SCRIPTS
		./kernel_compile.sh
		cd -
	fi

	# Build rootfs
	if [ $OPTION = "0" ]; then
		TMP_DISTRO="arch"
	elif [ $OPTION = "1" ]; then
		TMP_DISTRO="xenial"	
	elif [ $OPTION = "2" ]; then
		TMP_DISTRO="jessie"
	fi
	cd $SCRIPTS
	DISTRO=$TMP_DISTRO
	if [ -d $ROOT/output/rootfs ]; then
		if (whiptail --title "OrangePi Build System" --yesno \
			"${DISTRO} rootfs has exist! Do you want use it?" 10 60) then
			OP_ROOTFS=0
		else
			OP_ROOTFS=1
		fi

		if [ $OP_ROOTFS = "0" ]; then
			whiptail --title "OrangePi Build System" --msgbox "Rootfs has build" \
				10 40 0	--ok-button Continue
		else
			sudo -E bash -c "./build_rootfs.sh $DISTRO"
		fi

	else
		sudo -E bash -c "./build_rootfs.sh $DISTRO"
	fi

	# Package rootfs
	if [ $TMP = "0" ]; then 
		./build_image.sh $PLATFORM
		whiptail --title "OrangePi Build System" --msgbox "Succeed to build Image" \
				10 40 0	--ok-button Continue
	fi
	exit 0
elif [ $OPTION = "2" ]; then
	cd $SCRIPTS
	./uboot_compile.sh
	exit 0
elif [ $OPTION = "3" ]; then
	export BUILD_KERNEL=1
	export BUILD_MODULE=1
	cd $SCRIPTS
	./kernel_compile.sh
	exit 0
elif [ $OPTION = "4" ]; then
	export BUILD_KERNEL=1
	cd $SCRIPTS
	./kernel_compile.sh
	exit 0
elif [ $OPTION = "5" ]; then
	export BUILD_MODULE=1
	cd $SCRIPTS
	./kernel_compile.sh
	exit 0
elif [ $OPTION = "6" ]; then
	sudo echo ""
	clear
	UBOOT_check
	clear
	whiptail --title "OrangePi Build System" \
			 --msgbox "Burning Image to SDcard. Pls select Continue button" \
				10 40 0	--ok-button Continue
	pv "$ROOT/output/${PLATFORM}.img" | sudo dd bs=1M of=$UBOOT_PATH && sync
	clear
	whiptail --title "OrangePi Build System" --msgbox "Succeed to Download Image into SDcard" \
				10 40 0	--ok-button Continue
	exit 0
elif [ $OPTION = '7' ]; then
	clear 
	BOOT_check
	clear
	cd $SCRIPTS
	sudo ./kernel_update.sh $BOOT_PATH
	exit 0
elif [ $OPTION = '8' ]; then
	sudo echo ""
	clear 
	ROOTFS_check
	clear
	cd $SCRIPTS
	sudo ./modules_update.sh $ROOTFS_PATH
	exit 0
elif [ $OPTION = '9' ]; then
	clear
	UBOOT_check
	clear
	cd $SCRIPTS
	sudo ./uboot_update.sh $UBOOT_PATH
	exit 0
elif [ $OPTION = '10' ]; then
	clear
	echo -e "\e[1;31m Updating SDK to Github \e[0m"
	git push -u origin master
	exit 0
elif [ $OPTION = "11" ]; then
	clear
	echo -e "\e[1;31m Updating SDK from Github \e[0m"
	git push origin
	exit 0
else
	whiptail --title "OrangePi Build System" \
		--msgbox "Pls select correct option" 10 50 0
	exit 0
fi
