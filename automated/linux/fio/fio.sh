#!/bin/bash

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

TEST_PROGRAM=fio
TEST_PROG_VERSION=
TEST_GIT_URL=https://kernel.googlesource.com/pub/scm/linux/kernel/git/axboe/fio.git
TEST_DIR="$(pwd)/${TEST_PROGRAM}"
SKIP_INSTALL="false"
INSTALL_FROM_PKG="false"
DURATION="10m"
FIO_INSTALL_PATH="/opt/${TEST_PROGRAM}"

usage() {
	echo "\
	Usage: [sudo] ./fio.sh [-v <TEST_PROG_VERSION>] [-u <TEST_GIT_URL>]
				  [-p <TEST_DIR>] [-s <true|false>]
				  [-i <true|false>]

	<TEST_PROG_VERSION>:
	If this parameter is set, then the ${TEST_PROGRAM} is cloned. In
	particular, the version of the suite is set to the commit
	pointed to by the parameter. A simple choice for the value of
	the parameter is, e.g., HEAD. If, instead, the parameter is
	not set, then the suite present in TEST_DIR is used.

	<TEST_GIT_URL>:
	If this parameter is set, then the ${TEST_PROGRAM} is cloned
	from the URL in TEST_GIT_URL. Otherwise it is cloned from the
	standard repository for the suite. Note that cloning is done
	only if TEST_PROG_VERSION is not empty

	<TEST_DIR>:
	If this parameter is set, then the ${TEST_PROGRAM} suite is cloned to or
	looked for in TEST_DIR. Otherwise it is cloned to /opt/${TEST_PROGRAM}

	<SKIP_INSTALL>:
	If you already have it installed into the rootfs.
	default: false

	<INSTALL_FROM_PKG>:
        If user space want to install the pkg from the package repository.
	default: false"
}

while getopts "hp:u:i:s:v:" opt; do
	case $opt in
		u)
			if [[ "$OPTARG" != '' ]]; then
				TEST_GIT_URL="$OPTARG"
			fi
			;;
		p)
			if [[ "$OPTARG" != '' ]]; then
				TEST_DIR="$OPTARG"
			fi
			;;
		i)
			INSTALL_FROM_PKG="${OPTARG}"
			;;
		s)
			SKIP_INSTALL="${OPTARG}"
			;;
		v)
			TEST_PROG_VERSION="$OPTARG"
			;;
		h)
			usage
			exit 0
			;;
		*)
			usage
			exit 1
			;;
	esac
done

install() {
	dist=
	dist_name
	case "${dist}" in
		debian|ubuntu)
			pkgs="libaio1 libboost-iostreams1.71.0 libboost-thread1.71.0 libdaxctl1 libexpat1 libgfapi0 libgfrpc0 libgfxdr0 libglusterfs0 libgssapi-krb5-2 libibverbs1 libk5crypto3 libkeyutils1 libkmod2 libkrb5-3 libkrb5support0 libncursesw6 libndctl6 libnl-3-200 libnl-route-3-200 libnspr4 libnss3 libnuma1 libpmem1 libpmemblk1 libpython3-stdlib libpython3.8-minimal libpython3.8-stdlib librados2 librbd1 librdmacm1 libreadline8 libsqlite3-0 libssl1.1 libtirpc-common libtirpc3 mime-support python3 python3-minimal python3.8 python3.8-minimal readline-common"
			install_deps "${pkgs}" "${SKIP_INSTALL}"
			;;
		# When build do not have package manager
		# Assume dependencies pre-installed
		*)
			echo "Unsupported distro: ${dist}! Package installation skipped!"
			;;
	esac

}

install_from_pkg() {
	dist=
	dist_name
	case "${dist}" in
		debian|ubuntu)
			pkgs="fio"
			install_deps "${pkgs}" "${SKIP_INSTALL}"
			;;
		# When build do not have package manager
		# Assume dependencies pre-installed
		*)
			echo "Unsupported distro: ${dist}! Package installation skipped!"
			;;
	esac
}

build_install_tests() {
	dist=
	dist_name
	case "${dist}" in
		debian|ubuntu)
			pkgs="debhelper dpkg-dev libaio-dev zlib1g-dev librdmacm-dev libibverbs-dev librbd-dev libcairo2-dev libnuma-dev flex, bison libglusterfs-dev"
			install_deps "${pkgs}" "${SKIP_INSTALL}"
			;;
		# When build do not have package manager
		# Assume dependencies pre-installed
		*)
			echo "Unsupported distro: ${dist}! Package installation skipped!"
			;;
	esac

	pushd "$TEST_DIR" || exit 1
	./configure --disable-native --prefix="${FIO_INSTALL_PATH}"
	make -j"$(proc)" all
	make install
	popd || exit
	export PATH="${FIO_INSTALL_PATH} ${PATH}"
}

run_test() {
	fio

}

! check_root && error_msg "This script must be run as root"

# Install and run test

if [ "${SKIP_INSTALL}" = "true" ] || [ "${SKIP_INSTALL}" = "True" ]; then
	info_msg "Skip installing package dependency for ${TEST_PROG_VERSION}"
else
	install
fi

if [ "${INSTALL_FROM_PKG}" = "true" ] || [ "${INSTALL_FROM_PKG}" = "True" ]; then
	install_from_pkg
elif [ ! -d ${FIO_INSTALL_PATH} ]; then
	get_test_program "${TEST_GIT_URL}" "${TEST_DIR}" "${TEST_PROG_VERSION}" "${TEST_PROGRAM}"
	build_install_tests
else
	info_msg "Skip installing package dependency for ${TEST_PROG_VERSION}"
fi
create_out_dir "${OUTPUT}"
run_test
