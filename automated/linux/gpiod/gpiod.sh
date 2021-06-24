#!/bin/bash

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

GPIOD_PATH="/opt/libgpiod"

TEST_PROGRAM=gpiod
TEST_PROG_VERSION=
TEST_GIT_URL=https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git
TEST_DIR="$(pwd)/${TEST_PROGRAM}"
SKIP_INSTALL="false"

export RESULT_FILE

usage() {
	echo "\
	Usage: [sudo] ./gpiod.sh [-d <GPIOD_PATH>] [-v <TEST_PROG_VERSION>]
				  [-u <TEST_GIT_URL>] [-p <TEST_DIR>] [-s <true|false>]


	<GPIOD_PATH>:
	The pre-installed gpiod path GPIOD_PATH on the rootfs.

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
		looked for in TEST_DIR. Otherwise it is cloned to $(pwd)/${TEST_PROGRAM}

	<SKIP_INSTALL>:
	If you already have it installed into the rootfs.
	default: false"
}

while getopts "d:h:p:u:s:v:" opt; do
	case $opt in
		d)
			if [[ "$OPTARG" != '' ]]; then
				GPIOD_PATH="$OPTARG"
			fi
			;;
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
			pkgs="git libtool automake build-essential curl python3 m4 autoconf-archive"
			install_deps "${pkgs}" "${SKIP_INSTALL}"
			;;
		fedora|centos)
			pkgs="git-core libtool automake make gcc gcc-c++ curl python3 m4 autoconf-archive"
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
	pushd "${TEST_DIR}" || exit 1
	mkdir -p "${GPIOD_PATH}"
	./autogen.sh --enable-tools=yes --enable-tests=yes  --enable-bindings-cxx=yes --enable-bindings-python=yes --prefix="${GPIOD_PATH}"
	make
	make install
	make check
	popd || exit 1
}

if [ "${SKIP_INSTALL}" = "true" ] || [ "${SKIP_INSTALL}" = "True" ]; then
	info_msg "Skip installing package dependency for ${TEST_PROG_VERSION}"
else
	install
fi

get_test_program "${TEST_GIT_URL}" "${TEST_DIR}" "${TEST_PROG_VERSION}" "${TEST_PROGRAM}"

if [ ! -d "${GPIOD_PATH}/bin" ]; then
	build_install_tests
fi
create_out_dir "${OUTPUT}"
run_test

export PATH="${GPIOD_PATH}/bin:$PATH"
which gpiod-test || error_msg "'gpiod-test' not found, exiting..."
gpiod-test 2>&1| tee tmp.txt
sed 's/\[[0-9;]*m//g'  tmp.txt \
	| grep '\[TEST\]' \
	| sed 's/\[TEST\]//' \
	| sed -r "s/'//g; s/^ *//; s/-//; s/[^a-zA-Z0-9]/-/g; s/--+/-/g; s/-PASS/ pass/; s/-FAIL/ fail/; s/-SKIP/ skip/; s/-//;" 2>&1 \
	| tee -a result.txt
rm tmp.txt
