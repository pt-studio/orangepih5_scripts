#!/bin/bash
# Copyright (c) 2018 PT Studio
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

set -e
####################
# 
# This scripts is used to change different version.
# You need set ROOT and BUFFER path first!
# Create By: Buddy <buddy.zhang@aliyun.com>
# Date: 2017-01-05
# 
####################

if [ -z $ROOT ]; then
    export ROOT=`cd .. && pwd`
fi

if [ -z $1 ]; then
    BOARD="OrangePiH5_Zero_Plus2"
else
    BOARD=$1
fi

BUFFER="$ROOT/external/BUFFER"
BUFFER_FILE="$BUFFER/FILE"

## The absolute path of file
#kernel/.config
change_file=(
external/sys_config.fex
uboot/include/configs/sun50iw2p1.h
)

## The absolute path of dirent.
change_dirent=(
kernel/arch/arm64/boot/dts
)
name=""

# Chech all source have exist!
# If not, abort exchange!
function source_check()
{
    for file in ${change_file[@]}; do
        if [ ! -f ${ROOT}/${file} ]; then
           echo "${ROOT}/${file} doesn't exist!"
           exit 0
        fi  
    done

    # Change dirent
    for dirent in ${change_dirent[@]}; do
        if [ ! -d ${ROOT}/${dirent} ]; then
            echo "${ROOT}/${dirent} doesn't exist!" 
            exit 0
        fi
    done
}

# Exchange file and dirent
function change_version()
{
    echo 'Change board version'
    # Change file
    for file in ${change_file[@]}; do
       name=${file##*/}
       echo "  COPY: ${BUFFER_FILE}/${BOARD}_${name} $ROOT/$file"
       cp -f ${BUFFER_FILE}/${BOARD}_${name} $ROOT/$file
    done

    # Change dirent
    for dirent in ${change_dirent[@]}; do
        name=${dirent##*/}

        echo "  RSYNC: ${BUFFER_FILE}/${BOARD}_${name}/ => $ROOT/$dirent/"
        rsync -avz ${BUFFER}/${BOARD}_${name}/ $ROOT/$dirent/
    done
}

echo -e "\e[1;31m Setting up workspace for ${BOARD}\e[0m"

echo 'Restore origin file'
cp -f $ROOT/external/BUFFER/FILE/OrangePiH5_PC2_.config $ROOT/kernel/arch/arm64/configs/OrangePiH5_PC2_defconfig   
cp -f $ROOT/external/BUFFER/FILE/OrangePiH5_Prima_.config $ROOT/kernel/arch/arm64/configs/OrangePiH5_Prima_defconfig   
cp -f $ROOT/external/BUFFER/FILE/OrangePiH5_Zero_Plus2_.config $ROOT/kernel/arch/arm64/configs/OrangePiH5_Zero_Plus2_defconfig

cp -f $ROOT/external/BUFFER/FILE/OrangePiH5_PC2_sun50iw2p1.h $ROOT/uboot/include/configs/OrangePiH5_PC2_sun50iw2p1.h
cp -f $ROOT/external/BUFFER/FILE/OrangePiH5_Prima_sun50iw2p1.h $ROOT/uboot/include/configs/OrangePiH5_Prima_sun50iw2p1.h
cp -f $ROOT/external/BUFFER/FILE/OrangePiH5_Zero_Plus2_sun50iw2p1.h $ROOT/uboot/include/configs/OrangePiH5_Zero_Plus2_sun50iw2p1.h

cp -f $ROOT/external/BUFFER/FILE/OrangePiH5_PC2_sys_config.fex $ROOT/external/sys_config/OrangePiH5_PC2_sys_config.fex
cp -f $ROOT/external/BUFFER/FILE/OrangePiH5_Prima_sys_config.fex $ROOT/external/sys_config/OrangePiH5_Prima_sys_config.fex
cp -f $ROOT/external/BUFFER/FILE/OrangePiH5_Zero_Plus2_sys_config.fex $ROOT/external/sys_config/OrangePiH5_Zero_Plus2_sys_config.fex

echo 'Add kernel config'
#cp -f $ROOT/kernel/arch/arm64/configs/${BOARD}_defconfig $ROOT/kernel/.config
cp -f $ROOT/uboot/include/configs/${BOARD}_sun50iw2p1.h $ROOT/uboot/include/configs/sun50iw2p1.h
cp -f $ROOT/external/sys_config/${BOARD}_sys_config.fex $ROOT/external/sys_config.fex

change_version
source_check
