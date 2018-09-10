# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
# Copyright (c) 2018 PT Studio
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is contain some part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# create_chroot
# chroot_build_packages

# create_chroot <target_dir> <release> <arch>
#
create_chroot()
{
	local target_dir="$1"
	local release=$2
	local arch=$3

	declare -A qemu_binary apt_mirror components
	qemu_binary['armhf']='qemu-arm-static'
	qemu_binary['arm64']='qemu-aarch64-static'

	apt_mirror['xenial']="$UBUNTU_MIRROR"
	apt_mirror['bionic']="$UBUNTU_MIRROR"

	components['xenial']='main,universe,multiverse'
	components['bionic']='main,universe,multiverse'

	display_alert "Creating build chroot" "$release/$arch" "info"
	local includes="ccache,locales,git,ca-certificates,devscripts,libfile-fcntllock-perl,debhelper,rsync,python3,distcc"
	local mirror_addr="http://localhost:3142/${apt_mirror[$release]}"

	debootstrap --variant=buildd --components=${components[$release]} --arch=$arch --foreign --include="$includes" $release $target_dir $mirror_addr

	[[ $? -ne 0 || ! -f $target_dir/debootstrap/debootstrap ]] && exit_with_error "Create chroot first stage failed"

	cp /usr/bin/${qemu_binary[$arch]} $target_dir/usr/bin/

	[[ ! -f $target_dir/usr/share/keyrings/debian-archive-keyring.gpg ]] && \
		mkdir -p  $target_dir/usr/share/keyrings/ && \
		cp /usr/share/keyrings/debian-archive-keyring.gpg $target_dir/usr/share/keyrings/

	[[ ! -f $target_dir/usr/share/keyrings/ubuntu-archive-keyring.gpg ]] && \
		mkdir -p  $target_dir/usr/share/keyrings/ && \
		cp /usr/share/keyrings/ubuntu-archive-keyring.gpg $target_dir/usr/share/keyrings/

	chroot $target_dir /bin/bash -c "/debootstrap/debootstrap --second-stage"
	[[ $? -ne 0 || ! -f $target_dir/bin/bash ]] && exit_with_error "Create chroot second stage failed"

	create_sources_list "$release" "$target_dir"
	echo 'Acquire::http { Proxy "http://localhost:3142"; };' > $target_dir/etc/apt/apt.conf.d/02proxy

	cat <<-EOF > $target_dir/etc/apt/apt.conf.d/71-no-recommends
	APT::Install-Recommends "0";
	APT::Install-Suggests "0";
	EOF

	[[ -f $target_dir/etc/locale.gen ]] && sed -i "s/^# en_US.UTF-8/en_US.UTF-8/" $target_dir/etc/locale.gen
	chroot $target_dir /bin/bash -c "locale-gen; update-locale LANG=en_US:en LC_ALL=en_US.UTF-8"
	printf '#!/bin/sh\nexit 101' > $target_dir/usr/sbin/policy-rc.d
	chmod 755 $target_dir/usr/sbin/policy-rc.d

	rm $target_dir/etc/resolv.conf 2>/dev/null
	rm $target_dir/etc/hosts 2>/dev/null

	echo "127.0.0.1 localhost" > $target_dir/etc/hosts
	mkdir -p $target_dir/root/{build,overlay,sources} $target_dir/selinux

	if [[ -L $target_dir/var/lock ]]; then
		rm -rf $target_dir/var/lock 2>/dev/null
		mkdir -p $target_dir/var/lock
	fi

	chroot $target_dir /bin/bash -c "/usr/sbin/update-ccache-symlinks"
	touch $target_dir/root/.debootstrap-complete
	display_alert "Debootstrap complete" "$release/$arch" "info"
}

# chroot_build_packages
#
chroot_build_packages()
{
	local target_dir="$1"
	local release=xenial
	local arch=arm64

	[[ ! -f $target_dir/root/.debootstrap-complete ]] && create_chroot "$target_dir" "$release" "$arch"
	[[ ! -f $target_dir/root/.debootstrap-complete ]] && exit_with_error "Creating chroot failed" "$release/$arch"

	local t=$target_dir/root/.update-timestamp
	if [[ ! -f $t || $(( ($(date +%s) - $(<$t)) / 86400 )) -gt 7 ]]; then
		display_alert "Upgrading packages" "$release/$arch" "info"
		systemd-nspawn -a -q -D $target_dir /bin/bash -c "apt-get -q update; apt-get -q -y upgrade; apt-get clean"
		date +%s > $t
	fi

	for plugin in $SRC/external/packages/*.conf; do
		unset package_name package_repo package_ref package_builddeps package_install_chroot package_install_target \
			package_upstream_version needs_building plugin_target_dir package_component package_builddeps_${release}
		source $plugin

		# check build condition
		if [[ $(type -t package_checkbuild) == function ]] && ! package_checkbuild; then
			display_alert "Skipping building $package_name for" "$release/$arch"
			continue
		fi

		local plugin_target_dir=$OUTPUT_PATH/debs/$package_component/
		mkdir -p $plugin_target_dir

		# check if needs building
		local needs_building=no
		if [[ -n $package_install_target ]]; then
			for f in $package_install_target; do
				if [[ -z $(find $plugin_target_dir -name "${f}_*$REVISION*_$arch.deb") ]]; then
					needs_building=yes
					break
				fi
			done
		else
			needs_building=yes
		fi
		if [[ $needs_building == no ]]; then
			display_alert "Packages are up to date" "$package_name $release/$arch" "info"
			continue
		fi

		display_alert "Building packages" "$package_name $release/$arch" "ext"
		local dist_builddeps_name="package_builddeps_${release}"
		[[ -v $dist_builddeps_name ]] && package_builddeps="$package_builddeps ${!dist_builddeps_name}"

		# create build script
		cat <<- EOF > $target_dir/root/build.sh
		#!/bin/bash
		export PATH="/usr/lib/ccache:\$PATH"
		export HOME="/root"
		export DEBIAN_FRONTEND="noninteractive"
		export DEB_BUILD_OPTIONS="nocheck noautodbgsym"
		export CCACHE_TEMPDIR="/tmp"

		export http_proxy=http://127.0.0.1:3142/
		export https_proxy=http://10.158.100.6:8080

		$(declare -f display_alert)

		cd /root/build
		if [[ -n "$package_builddeps" ]]; then
			# can be replaced with mk-build-deps
			deps=()
			installed=\$(dpkg-query -W -f '\${db:Status-Abbrev}|\${binary:Package}\n' '*' 2>/dev/null | grep '^ii' | awk -F '|' '{print \$2}' | cut -d ':' -f 1)
			for packet in $package_builddeps; do grep -q -x -e "\$packet" <<< "\$installed" || deps+=("\$packet"); done
			if [[ \${#deps[@]} -gt 0 ]]; then
				display_alert "Installing build dependencies"
				apt-get -y -q update
				apt-get -y -q --no-install-recommends --show-progress -o DPKG::Progress-Fancy=1 install "\${deps[@]}"
			fi
		fi

		display_alert "Copying sources"
		rsync -aq /root/sources/$package_name /root/build/
		cd /root/build/$package_name
		# copy overlay / "debianization" files
		[[ -d "/root/overlay/$package_name/" ]] && rsync -aq /root/overlay/$package_name /root/build/

		display_alert "Building package"
		dpkg-buildpackage -b -uc -us -j2

		if [[ \$? -eq 0 ]]; then
			cd /root/build
			# install in chroot if other libraries depend on them
			if [[ -n "$package_install_chroot" ]]; then
				display_alert "Installing packages"
				for p in $package_install_chroot; do
					dpkg -i \${p}_*.deb
				done
			fi
			display_alert "Done building" "$package_name $release/$arch" "ext"
			ls *.deb 2>/dev/null
			mv *.deb /root 2>/dev/null
			exit 0
		else
			display_alert "Failed building" "$package_name $release/$arch" "err"
			exit 2
		fi
		EOF

		chmod a+x $target_dir/root/build.sh
		eval systemd-nspawn -a -q \
			--capability=CAP_MKNOD \
			-D $target_dir \
			--tmpfs=/root/build \
			--tmpfs=/tmp:mode=777 \
			--bind-ro $SRC/cache/sources/:/root/sources \
			--bind-ro $SRC/external/packages/:/root/overlay \
			/bin/bash -c "/root/build.sh" 2>&1

		ls $target_dir/root/*.deb | grep deb && mv $target_dir/root/*.deb $plugin_target_dir 2>/dev/null
	done

}

# chroot_installpackages_local
#
chroot_installpackages_local()
{
	local conf=$EXTERNAL_PATH/aptly-temp.conf
	rm -rf /tmp/aptly-temp/
	mkdir -p /tmp/aptly-temp/
	RELEASE=xenial
	aptly -config=$conf repo create temp
	# NOTE: this works recursively
	aptly -config=$conf repo add temp $OUTPUT_PATH/debs/${RELEASE}-desktop/
	aptly -config=$conf repo add temp $OUTPUT_PATH/debs/${RELEASE}-utils/
	# -gpg-key="925644A6"
	#aptly -keyring="$EXTERNAL_PATH/buildpkg-public.gpg" -secret-keyring="$EXTERNAL_PATH/buildpkg.gpg" -batch=true -config=$conf \
	#	 -gpg-key="925644A6" -passphrase="testkey1234" -component=temp -distribution=$RELEASE publish repo temp
	aptly -batch=true -config=$conf \
		 -component=temp -distribution=$RELEASE \
		publish repo temp
	aptly -config=$conf -listen=":8189" serve &
	local aptly_pid=$!
	cp $EXTERNAL_PATH/buildpkg.key $SDCARD/tmp/buildpkg.key
	cat <<-'EOF' > $SDCARD/etc/apt/preferences.d/90-armbian-temp.pref
	Package: *
	Pin: origin "localhost"
	Pin-Priority: 550
	EOF
	cat <<-EOF > $SDCARD/etc/apt/sources.list.d/armbian-temp.list
	deb http://localhost:8189/ $RELEASE temp
	EOF
	chroot_installpackages
	kill $aptly_pid
}

# chroot_installpackages <remote_only>
#
chroot_installpackages()
{
	local remote_only=$1
	local install_list=""

	display_alert "Installing additional packages" "EXTERNAL_NEW"
	for plugin in $EXTERNAL_PATH/packages/*.conf; do
		source $plugin
		if [[ $(type -t package_checkinstall) == function ]] && package_checkinstall; then
			install_list="$install_list $package_install_target"
		fi
		unset package_install_target package_checkinstall
	done

	local apt_extra="-o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\" -o Acquire::http::Proxy::localhost=\"DIRECT\""
	cat <<-EOF > $SDCARD/tmp/install.sh
	#!/bin/bash
	[[ "$remote_only" != yes ]] && apt-key add /tmp/buildpkg.key
	apt-get $apt_extra -q update
	# uncomment to debug
	# /bin/bash
	# TODO: check if package exists in case new config was added
	#if [[ -n "$remote_only" == yes ]]; then
	#	for p in $install_list; do
	#		if grep -qE "apt.armbian.com|localhost" <(apt-cache madison \$p); then
	#		if apt-get -s -qq install \$p; then
	#fi
	apt-get -q $apt_extra --show-progress -o DPKG::Progress-Fancy=1 install -y $install_list
	apt-get clean
	[[ "$remote_only" != yes ]] && apt-key del "925644A6"
	rm /etc/apt/sources.list.d/armbian-temp.list 2>/dev/null
	rm /etc/apt/preferences.d/90-armbian-temp.pref 2>/dev/null
	rm /tmp/buildpkg.key 2>/dev/null
	rm -- "\$0"
	EOF
	chmod +x $SDCARD/tmp/install.sh
	cp -f /usr/bin/qemu-aarch64-static $SDCARD/usr/bin/
	chroot $SDCARD /bin/bash -c "/tmp/install.sh"
	#rm -f "$SRCFS_PATH/usr/bin/qemu-aarch64-static"
}
