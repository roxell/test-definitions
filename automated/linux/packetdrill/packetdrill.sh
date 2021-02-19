#!/bin/bash

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

TEST_PROGRAM=packetdrill
TEST_PROG_VERSION=
TEST_GIT_URL=https://github.com/google/packetdrill.git
TEST_DIR="/opt/${TEST_PROGRAM}"
SKIP_INSTALL="false"
DURATION="10m"

usage() {
	echo "\
	Usage: [sudo] ./packetdrill.sh [-d <DURATION>] [-v <TEST_PROG_VERSION>]
				  [-u <TEST_GIT_URL>] [-p <TEST_DIR>] [-s <true|false>]

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
	default: false"
}

while getopts "hp:u:s:v:" opt; do
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
			pkgs="curl git bison flex"
			install_deps "${pkgs}" "${SKIP_INSTALL}"
			;;
		fedora|centos)
			pkgs="curl git-core bison flex"
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
    pushd "${TEST_DIR}/gtests/net/packetdrill" || exit 1
    ./configure
    make -j"$(proc)" all
    popd || exit 1
}

run_test() {
    pushd "${TEST_DIR}/gtests/net" || exit 1
    ./packetdrill/run_all.py -S -v -L -l tcp/
    popd || exit 1

}

! check_root && error_msg "This script must be run as root"

# Install and run test

if ! command -v cyclictest > /dev/null; then
	install_rt_tests
fi

if [ "${SKIP_INSTALL}" = "true" ] || [ "${SKIP_INSTALL}" = "True" ]; then
	info_msg "Skip installing package dependency for ${TEST_PROG_VERSION}"
else
	install
fi

get_test_program "${TEST_GIT_URL}" "${TEST_DIR}" "${TEST_PROG_VERSION}" "${TEST_PROGRAM}"
build_install_tests
create_out_dir "${OUTPUT}"
run_test
