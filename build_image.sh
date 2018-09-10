# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
# Copyright (c) 2018 PT Studio
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is contain some part of the Armbian build script
# https://github.com/armbian/build/

boot0_position=8      # KiB
uboot_position=16400  # KiB
part_position=20480   # KiB

OFFSET=$(( $part_position * 2 / 1024 ))   #MiB
BOOTSIZE=64 #MiB 

write_uboot() {
    boot0="$SRC/output/boot/boot0.bin"
    uboot="$SRC/output/boot/uboot.bin"

    display_alert "Install Bootloader" "$1"
    display_alert "Writing data" "SPL"
    dd if="$boot0" conv=notrunc bs=1k seek=$boot0_position of="$1"
    display_alert "Writing data" "uBoot"
    dd if="$uboot" conv=notrunc bs=1k seek=$uboot_position of="$1"
}

create_image() {
	local IMAGE="/vagrant/output/${BOARD}.img"

    # Stage 1: Create blank image
    losetup -D

    display_alert "Preparing image file for rootfs" "$BOARD $DISTRO" "info"
    # step: calculate rootfs size
    local rootfs_size=$(du -sm $SDCARD | cut -f1) # MiB
    display_alert "Current rootfs size" "$rootfs_size MiB" "info"

    local imagesize=$(( $rootfs_size + $OFFSET + $BOOTSIZE )) # MiB
    local sdsize=$(bc -l <<< "scale=0; ((($imagesize * 1.25) / 1 + 0) / 4 + 1) * 4")

    # step: create blank image
    display_alert "Creating blank image for rootfs" "$sdsize MiB" "info"
    dd if=/dev/zero bs=1M status=none count=$sdsize | pv -p -b -r -s $(( $sdsize * 1024 * 1024 )) | dd status=none of=${SDCARD}.raw

    # step: calculate boot partition size
    local bootstart=$(($OFFSET * 2048))
    local rootstart=$(($bootstart + ($BOOTSIZE * 2048)))
    local bootend=$(($rootstart - 1))

    # step: create partition table
    display_alert "Creating partitions" "boot: fat32 | root: ext4" "info"

    parted -s ${SDCARD}.raw -- mklabel msdos
    parted -s ${SDCARD}.raw -- mkpart primary fat32 ${bootstart}s ${bootend}s
    parted -s ${SDCARD}.raw -- mkpart primary ext4 ${rootstart}s -1s

    sync

    # Stage 2: Create loop device
    local LOOP=$(losetup -f)
    losetup $LOOP ${SDCARD}.raw

    partprobe $LOOP

    # Stage 3: Format loop device
    local bootlodev="${LOOP}p1"
    local rootlodev="${LOOP}p2"
    display_alert "Creating bootfs" "vfat"
    mkfs.vfat -n BOOT $bootlodev
    display_alert "Creating rootfs" "ext4"
    mkfs.ext4 -O ^64bit,^metadata_csum -F -b 4096 -E stride=2,stripe-width=1024 -L rootfs $rootlodev
	tune2fs -o journal_data_writeback $rootlodev > /dev/null

    # Stage 4: Create uboot config and fstab
    local bootfs_mount="/tmp/orangepi_bootfs"
    local rootfs_mount="/tmp/orangepi_rootfs"

    #
    [[ -d $bootfs_mount ]] && umount $bootfs_mount >/dev/null 2>&1 || true
    [[ -d $rootfs_mount ]] && umount $rootfs_mount >/dev/null 2>&1 || true

    #
    mkdir -p $bootfs_mount
    mount -t vfat $bootlodev $bootfs_mount
    local bootdev="UUID=$(blkid -s UUID -o value $bootlodev)"
    display_alert "Boot device" $bootdev

    #
    mkdir -p $rootfs_mount
    mount -t ext4 $rootlodev $rootfs_mount
    local rootdev="UUID=$(blkid -s UUID -o value $rootlodev)"
    display_alert "Rootfs UUID" $rootdev

    # step: create uEnv.txt
    display_alert "Create uEnv.txt"
cat <<EOF > "$SRC/output/boot/uEnv.txt"
console=tty0 console=ttyS0,115200n8 no_console_suspend
cma=96M
kernel_filename=orangepi/uImage
initrd_filename=initrd_sdcard.gz

root=${rootfs}

EOF

    # step: create fs, mount partitions, create fstab
    display_alert "Create fstab"
    rm -f $SDCARD/etc/fstab
    echo "$bootdev /boot vfat defaults 1 2" >> $SDCARD/etc/fstab
    echo "$rootdev / ext4 defaults,noatime,nodiratime,commit=600,errors=remount-ro 1 1" >> $SDCARD/etc/fstab
    echo "tmpfs /tmp tmpfs defaults,nosuid 0 0" >> $SDCARD/etc/fstab

    # Stage 5: Copy files to loop device
    display_alert "Copying files to boot directory"
    rsync -rLtWh --info=progress2,stats1 $SRC/output/boot/ $bootfs_mount/
    sync

    display_alert "Copying files to root directory"
    rsync -aHWXh \
        --exclude="/boot/*" \
        --exclude="/dev/*" \
        --exclude="/proc/*" \
        --exclude="/run/*" \
        --exclude="/tmp/*" \
        --exclude="/sys/*" \
        --info=progress2,stats1 $SDCARD/ $rootfs_mount

    sync

    # Final: Make image bootable
    write_uboot $LOOP

    umount $bootfs_mount
    umount $rootfs_mount
    losetup -D

	mv ${SDCARD}.raw $IMAGE
	sync
	display_alert "Done building" "$IMAGE" "info"
}

build_image() {
    create_image

}

# -----------------------------------------------------------------------------
