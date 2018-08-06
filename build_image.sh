#!/bin/bash
################################################################
##
##
## Build Release Image
################################################################
set -e

export PATH=$PATH:/sbin:/usr/local/sbin:/usr/sbin

if [ -z $ROOT ]; then
	ROOT=`cd .. && pwd`
fi

if [ -z $1 ]; then
	PLATFORM="OrangePiH5_Zero_Plus2"
else
	PLATFORM=$1
fi

BUILD="$ROOT/external"
OUTPUT="$ROOT/output"
IMAGE="$OUTPUT/${PLATFORM}.img"
ROOTFS="$OUTPUT/rootfs"
disk_size="768"

if [ -z "$disk_size" ]; then
	disk_size=100 #MiB
fi

if [ "$disk_size" -lt 60 ]; then
	echo "Disk size must be at least 60 MiB"
	exit 2
fi

echo "Creating image $IMAGE of size $disk_size MiB ..."

boot0="$ROOT/output/boot0.bin"
uboot="$ROOT/output/uboot.bin"

# Partition Setup
boot0_position=8      # KiB
uboot_position=16400  # KiB
part_position=20480   # KiB
boot_size=50          # MiB

set -x

# # Create beginning of disk
echo 'Cleaning'
dd if=/dev/zero bs=1M count=${disk_size} of="$IMAGE"

echo 'Install Bootloader'
echo '> SPL'
dd if="$boot0" conv=notrunc bs=1k seek=$boot0_position of="$IMAGE"
echo '> uBoot'
dd if="$uboot" conv=notrunc bs=1k seek=$uboot_position of="$IMAGE"

# Add partition table
cat <<EOF | fdisk "$IMAGE"
o
n
p
1
$((part_position*2))
+${boot_size}M
t
c
n
p
2
$((part_position*2 + boot_size*1024*2))

t
2
83
w
EOF

losetup -D
losetup -Pf "$IMAGE"

# Create boot file system (VFAT)
mkfs.vfat -n BOOT /dev/loop0p1

rm -rf $OUTPUT/orangepi
mkdir -p $OUTPUT/orangepi
cp $OUTPUT/uImage $OUTPUT/orangepi
cp $OUTPUT/OrangePiH5.dtb $OUTPUT/orangepi/OrangePiH5.dtb

# Add boot support if there
mcopy -sm -i /dev/loop0p1 ${OUTPUT}/orangepi ::
mcopy -m -i /dev/loop0p1 ${OUTPUT}/initrd.img :: || true
mcopy -m -i /dev/loop0p1 ${OUTPUT}/initrd_sdcard.gz :: || true
mcopy -m -i /dev/loop0p1 ${OUTPUT}/uEnv.txt :: || true

# Create additional ext4 file system for rootfs
umount /media/tmp || true
mkfs.ext4 -F -b 4096 -E stride=2,stripe-width=1024 -L rootfs /dev/loop0p2
#mkfs.ext4 -F -b 4096 -L rootfs /dev/loop0p2

if [ ! -d /media/tmp ]; then
	mkdir -p /media/tmp
fi

mount -t ext4 /dev/loop0p2 /media/tmp
# Add rootfs into Image
rsync -avz $OUTPUT/rootfs/ /media/tmp/

umount /media/tmp
losetup -D

if [ -d $OUTPUT/orangepi ]; then
	rm -rf $OUTPUT/orangepi
fi 

if [ -d /media/tmp ]; then
	rm -rf /media/tmp
fi

sync
