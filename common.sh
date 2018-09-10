# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
# Copyright (c) 2018 PT Studio
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is contain some part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# cleaning
# exit_with_error
# create_sources_list
# display_alert
# prepare_host

# cleaning <target>
#
# target: what to clean
# "make" - "make clean" for selected kernel and u-boot
# "debs" - delete output/debs
# "cache" - delete output/cache
# "images" - delete output/images
# "sources" - delete output/sources
#
cleaning()
{
	case $1 in
		debs) # delete output/debs for current branch and family
		if [[ -d $DEST/debs ]]; then
			display_alert "Cleaning output/debs for" "$BOARD $BRANCH" "info"
			rm -rf $DEST/debs
		fi
		;;

		cache) # delete output/cache
		[[ -d $SRC/cache/rootfs ]] && display_alert "Cleaning" "rootfs cache (all)" "info" && find $SRC/cache/rootfs -type f -delete
		;;

		images) # delete output/images
		[[ -d $DEST/images ]] && display_alert "Cleaning" "output/images" "info" && rm -rf $DEST/images/*
		;;

		sources) # delete output/sources and output/buildpkg
		[[ -d $SRC/cache/sources ]] && display_alert "Cleaning" "sources" "info" && rm -rf $SRC/cache/sources/* $DEST/buildpkg/*
		;;

		oldcache)
		if [[ -d $SRC/cache/rootfs && $(ls -1 $SRC/cache/rootfs/*.lz4 | wc -l) -gt ${ROOTFS_CACHE_MAX} ]]; then
			display_alert "Cleaning" "rootfs cache (old)" "info"
			(cd $SRC/cache/rootfs; ls -t *.lz4 | sed -e "1,${ROOTFS_CACHE_MAX}d" | xargs -d '\n' rm -f)
			# Remove signatures if they are present. We use them for internal purpose
			(cd $SRC/cache/rootfs; ls -t *.asc | sed -e "1,${ROOTFS_CACHE_MAX}d" | xargs -d '\n' rm -f)
		fi
		;;
	esac
}

# exit_with_error <message> <highlight>
exit_with_error() {
	local _file=$(basename ${BASH_SOURCE[1]})
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _description=$1
	local _highlight=$2

	display_alert "ERROR in function $_function" "$_file:$_line" "err"
	display_alert "$_description" "$_highlight" "err"
	display_alert "Process terminated" "" "info"

	exit -1
}

# display_alert <message> <tag> <mesg type>
display_alert() {
	local tmp=""
	[[ -n $2 ]] && tmp="[\e[0;33m $2 \x1B[0m]"

	case $3 in
		err)
		echo -e "[\e[0;31m error \x1B[0m] $1 $tmp"
		;;

		wrn)
		echo -e "[\e[0;35m warn \x1B[0m] $1 $tmp"
		;;

		ext)
		echo -e "[\e[0;32m o.k. \x1B[0m] \e[1;32m$1\x1B[0m $tmp"
		;;

		info)
		echo -e "[\e[0;32m o.k. \x1B[0m] $1 $tmp"
		;;

		*)
		echo -e "[\e[0;32m .... \x1B[0m] $1 $tmp"
		;;
	esac
}

# create_sources_list <release> <basedir>
#
# <release>: xenial|bionic
# <basedir>: path to root directory
#
create_sources_list()
{
	local release=$1
	local basedir=$2
	[[ -z $basedir ]] && exit_with_error "No basedir passed to create_sources_list"

	case $release in
	xenial|bionic)
	cat <<-EOF > $basedir/etc/apt/sources.list
	deb http://${UBUNTU_MIRROR} $release main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} $release main restricted universe multiverse
	deb http://${UBUNTU_MIRROR} ${release}-security main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-security main restricted universe multiverse
	deb http://${UBUNTU_MIRROR} ${release}-updates main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-updates main restricted universe multiverse
	deb http://${UBUNTU_MIRROR} ${release}-backports main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-backports main restricted universe multiverse
	EOF
	;;
	esac
}

# prepare_host
#
# * checks and installs necessary packages
# * creates directory structure
# * changes system settings
#
prepare_host()
{
	display_alert "Preparing" "host" "info"

	if [[ $(dpkg --print-architecture) != amd64 ]]; then
		display_alert "Please read documentation to set up proper compilation environment"
		display_alert "http://www.armbian.com/using-armbian-tools/"
		exit_with_error "Running this tool on non x86-x64 build host in not supported"
	fi

	# need lsb_release to decide what to install
	if [[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' lsb-release 2>/dev/null) != *ii* ]]; then
		display_alert "Installing package" "lsb-release"
		apt -q update && apt install -q -y --no-install-recommends lsb-release
	fi

	# packages list for host
	# NOTE: please sync any changes here with the Dockerfile and Vagrantfile
	local hostdeps="wget ca-certificates device-tree-compiler pv bc lzop zip binfmt-support build-essential ccache debootstrap ntpdate \
	gawk gcc-arm-linux-gnueabihf qemu-user-static u-boot-tools uuid-dev zlib1g-dev unzip libusb-1.0-0-dev fakeroot \
	parted pkg-config libncurses5-dev whiptail debian-keyring debian-archive-keyring f2fs-tools libfile-fcntllock-perl rsync libssl-dev \
	nfs-kernel-server btrfs-tools ncurses-term p7zip-full kmod dosfstools libc6-dev-armhf-cross \
	curl patchutils python liblz4-tool libpython2.7-dev linux-base swig libpython-dev aptly acl \
	locales ncurses-base pixz dialog systemd-container udev lib32stdc++6 libc6-i386 lib32ncurses5 lib32tinfo5 \
	bison libbison-dev flex libfl-dev"

	local codename=$(lsb_release -sc)
	display_alert "Build host OS release" "${codename:-(unknown)}" "info"

	if [[ -z $codename || "xenial bionic" != *"$codename"* ]]; then
		display_alert "You are running on an unsupported system" "${codename:-(unknown)}" "wrn"
		display_alert "Do not report any errors, warnings or other issues encountered beyond this point" "" "wrn"
	fi

	if grep -qE "(Microsoft|WSL)" /proc/version; then
		exit_with_error "Windows subsystem for Linux is not a supported build environment"
	fi

	# warning: apt-cacher-ng will fail if installed and used both on host and in container/chroot environment with shared network
	hostdeps="$hostdeps apt-cacher-ng"

	local deps=()
	local installed=$(dpkg-query -W -f '${db:Status-Abbrev}|${binary:Package}\n' '*' 2>/dev/null | grep '^ii' | awk -F '|' '{print $2}' | cut -d ':' -f 1)

	for packet in $hostdeps; do
		if ! grep -q -x -e "$packet" <<< "$installed"; then deps+=("$packet"); fi
	done

	# distribution packages are buggy, download from author
	if [[ ! -f /etc/apt/sources.list.d/aptly.list ]]; then
		display_alert "Updating from external repository" "aptly" "info"
		apt-key adv --keyserver pool.sks-keyservers.net --recv-keys ED75B5A4483DA07C >/dev/null 2>&1
		echo "deb http://repo.aptly.info/ squeeze main" > /etc/apt/sources.list.d/aptly.list
	fi

	if [[ ${#deps[@]} -gt 0 ]]; then
		display_alert "Installing build dependencies"
		apt -q update
		apt -y upgrade
		apt -q -y --no-install-recommends install "${deps[@]}" | tee -a $DEST/hostdeps.log
		update-ccache-symlinks
	fi

	# Temorally broken in Bionic, reverting to prvious version
	# https://github.com/aptly-dev/aptly/issues/740
	if [[ $(dpkg -s aptly | grep '^Version:' | sed 's/Version: //') != "1.2.0" && "$codename" == "bionic" ]]; then
		apt -qq -y --allow-downgrades install aptly=1.2.0
	fi

	if [[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' 'zlib1g:i386' 2>/dev/null) != *ii* ]]; then
		apt install -qq -y --no-install-recommends zlib1g:i386 >/dev/null 2>&1
	fi

	# create directory structure
	mkdir -p $SRC/{cache,output}
	mkdir -p $SRC/cache/{sources,rootfs}
	mkdir -p $DEST/{debs,tmp}/

	# check free space (basic)
	local freespace=$(findmnt --target $SRC -n -o AVAIL -b 2>/dev/null) # in bytes
	if [[ -n $freespace && $(( $freespace / 1073741824 )) -lt 10 ]]; then
		display_alert "Low free space left" "$(( $freespace / 1073741824 )) GiB" "wrn"
		# pause here since dialog-based menu will hide this message otherwise
		echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m to abort compilation, \e[0;33m<Enter>\x1B[0m to ignore and continue"
		read
	fi
}

