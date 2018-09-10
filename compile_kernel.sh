# Copyright (c) 2018 PT Studio
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

export LINUXSOURCEDIR="$SRC/kernel"

clean_kernel() {
	display_alert "Clean" "linux" "info"
	make -C $LINUXSOURCEDIR ARCH=arm64 CROSS_COMPILE="$LINUX_TOOLCHAIN" clean mrproper
}

compile_kernel() {
	display_alert "Config ${BOARD}_linux_defconfig" "linux" "warn"
	make -C $LINUXSOURCEDIR ARCH=arm64 CROSS_COMPILE="$LINUX_TOOLCHAIN" ${BOARD}_defconfig

	display_alert "Compile" "linux" "info"
	make -j${CORES} -C $LINUXSOURCEDIR ARCH=arm64 CROSS_COMPILE="$LINUX_TOOLCHAIN" Image dtbs

	# Perpare uImage
	display_alert "Compile uImage" "linux" "info"
	mkdir -p $OUTPUT_PATH/boot/orangepi/
	mkimage -A arm -n "OrangePiH5" -O linux -T kernel \
		-C none -a 0x40080000 -e 0x40080000 \
		-d $LINUXSOURCEDIR/arch/arm64/boot/Image $OUTPUT_PATH/boot/orangepi/uImage

	## Build initrd.img
	display_alert "Build initrd.img"
	cp -rfa $SRC/external/blobs/initrd.img $OUTPUT_PATH/boot
	cp -rfa $SRC/external/blobs/initrd_sdcard.gz $OUTPUT_PATH/boot
}

compile_kernel_modules() {
	if [ ! -d $OUTPUT_PATH/lib ]; then
		mkdir -p $OUTPUT_PATH/lib
	fi 

	if [ ! -f $LINUXSOURCEDIR/.config ]; then
		display_alert "Config ${BOARD}_linux_defconfig" "linux" "info"
		make -C $LINUXSOURCEDIR ARCH=arm64 CROSS_COMPILE="$LINUX_TOOLCHAIN" ${BOARD}_defconfig
	fi
	
	kernel_version=`cat $LINUXSOURCEDIR/include/config/kernel.release 2> /dev/null`

	# make dts
	compile_kernel_dts

	# make module
	display_alert "Compile modules" "linux" "info"
	make -j${CORES} -C $LINUXSOURCEDIR ARCH=arm64 CROSS_COMPILE="$LINUX_TOOLCHAIN" \
		modules

	# Install module
	display_alert "Install modules" "target" "info"
	make -j${CORES} -C $LINUXSOURCEDIR ARCH=arm64 CROSS_COMPILE="$LINUX_TOOLCHAIN" \
		INSTALL_MOD_PATH=$OUTPUT_PATH \
		modules_install
	
	display_alert "Install kernel firmware" "target" "info"
	make -C $LINUXSOURCEDIR ARCH=arm64 CROSS_COMPILE="${LINUX_TOOLCHAIN}" \
		INSTALL_MOD_PATH="$OUTPUT_PATH" firmware_install

	# ---------------------------------------------------------------------------------------------
	# Compile Mali450 driver
	display_alert "Compile mali 450" "linux" "info"
	MALI_VERSION="r5p1-01rel0"
	MALI_DRIVER="$SRC/cache/sources/mali-${MALI_VERSION}"
	make -C $MALI_DRIVER ARCH=arm64 CROSS_COMPILE="$LINUX_TOOLCHAIN" \
		ARCH=arm64 \
		LICHEE_KDIR=$LINUXSOURCEDIR \
		LICHEE_PLATFORM=linux \
		BUILD=release clean build

	# Copy all kernel modules
	MALI_MOD_DIR=$OUTPUT_PATH/lib/modules/$kernel_version/kernel/drivers/gpu
	display_alert "Install custom module" "target" "info"
	for i in `find $MALI_DRIVER | grep \.ko$`; do
		fname=${file##*/}
		cp -vf $i $MALI_MOD_DIR/$fname
	done

	# ---------------------------------------------------------------------------------------------

	display_alert "Depmod ${kernel_version}" "target" "info"
	depmod -b $OUTPUT_PATH $kernel_version

}

compile_kernel_dts() {
	display_alert "Cover sys_config.fex to DTS" "target" "info"
	cd $SRC/scripts/pack/
	./pack
	cd -

}

build_kernel() {
	clean_kernel
	compile_kernel
	compile_kernel_modules
}
