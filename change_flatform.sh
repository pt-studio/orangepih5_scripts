#!/bin/bash
set -e
########################################
##
## Change different platform
########################################
if [ -z $ROOT ]; then
	export ROOT=`cd .. && pwd`
fi

if [ -z $1 ]; then
	PLATFORM="OrangePiH5_PC2"
else
	PLATFORM=$1
fi

VERSION=$ROOT/scripts/version
# Create Version state file
if [ ! -f $VERSION ]; then
	echo "$PLATFORM" > $VERSION
fi
OLD_PLATFORM=`cat $VERSION`
./change_flatform_check.sh "$OLD_PLATFORM"

if [ $PLATFORM = $OLD_PLATFORM ]; then
	exit 0
fi 

echo "$PLATFORM" > $VERSION

#####
# Exchange File and Dirent
./change_flatform_apply.sh "$PLATFORM" "$OLD_PLATFORM"
