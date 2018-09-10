#!/bin/bash
# Copyright (c) 2018 PT Studio
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

set -e

#################################
## Compile U-boot
## This script will compile u-boot and merger with scripts.bin, bl31.bin and dtb.
#################################
BOOTSOURCEDIR=$SRC/uboot

clean_uboot() {
	display_alert "Clean" "uboot" "info"
	make -C $BOOTSOURCEDIR clean
	rm -f $BOOTSOURCEDIR/u-boot-sun50iw2p1.bin
	rm -f $BOOTSOURCEDIR/sunxi_spl/boot0/boot0_sdcard.bin
}

compile_uboot() {
	cd $BOOTSOURCEDIR

	if [ ! -f $BOOTSOURCEDIR/u-boot-sun50iw2p1.bin ]; then
		display_alert "Config sun50iw2p1_config" "uboot" "info"
		make -j${CORES} CROSS_COMPILE="${UBOOT_TOOLCHAIN}" sun50iw2p1_config
	fi

	display_alert "Compile" "uboot" "info"
	make -j${CORES} CROSS_COMPILE="${UBOOT_TOOLCHAIN}"

	if [ ! -f $BOOTSOURCEDIR/sunxi_spl/boot0/boot0_sdcard.bin ]; then
		display_alert "Compile boot0" "uboot" "info"
		make -j${CORES} CROSS_COMPILE="${UBOOT_TOOLCHAIN}" sun50iw2p1_config
	fi

	display_alert "Compile spl" "uboot" "info"
	make CROSS_COMPILE="${UBOOT_TOOLCHAIN}" spl 
	cd -

	# Merge uboot with different binary
	display_alert "Pack" "uboot" "info"
	cd $SRC/scripts/pack/
	./pack

	# Copy output file
	mkdir -p $OUTPUT_PATH/boot
	cp -f $OUTPUT_PATH/pack/out/boot0_sdcard.fex $OUTPUT_PATH/boot/boot0.bin
	cp -f $OUTPUT_PATH/pack/out/boot_package.fex $OUTPUT_PATH/boot/uboot.bin

	cd -
}
