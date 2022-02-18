#!/bin/bash

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
RESULT_LOG="${OUTPUT}/result_log.txt"
TMP_LOG="${OUTPUT}/tmp_log.txt"
TEST_PASS_LOG="${OUTPUT}/test_pass_log.txt"
TEST_FAIL_LOG="${OUTPUT}/test_fail_log.txt"
TEST_SKIP_LOG="${OUTPUT}/test_skip_log.txt"
TEST_METRIC_LOG="${OUTPUT}/test_metric_log.txt"

TEST_PROGRAM=vdso
TEST_PROG_VERSION=
TEST_GIT_URL=https://kernel.googlesource.com/pub/scm/utils/vdso/vdso.git
TEST_DIR="$(pwd)/${TEST_PROGRAM}"
SKIP_INSTALL="false"
API=""
DURATION=""
VDSOTESTALL="yes"
TEST_TYPE=""
usage() {
	echo "\
	Usage: [sudo] ./vdso.sh [-a <API>]
				[-d <DURATION>]
				[-f <ALL>]
				[-t <TEST-TYPE>]
				[-v <TEST_PROG_VERSION>]
				[-u <TEST_GIT_URL>]
				[-p <TEST_DIR>]
				[-s <true|false>]

	<API>:
	where API must be one of:
	clock-gettime-monotonic
	clock-getres-monotonic
	clock-gettime-monotonic-coarse
	clock-getres-monotonic-coarse
	clock-gettime-monotonic-raw
	clock-getres-monotonic-raw
	clock-gettime-tai
	clock-getres-tai
	clock-gettime-boottime
	clock-getres-boottime
	clock-gettime-realtime
	clock-getres-realtime
	clock-gettime-realtime-coarse
	clock-getres-realtime-coarse
	getcpu
	gettimeofday

	<DURATION>:
	Time in long will the test be running. DURATION can be set
	to X
	default: 1s - seconds
	
	<ALL>:
	Run all tests
	default: all

	<TEST_TYPE>:
	TEST_TYPE must be one of:
	verify
	bench
	abi

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

while getopts "a:d:f:t:hk:p:u:s:v:" opt; do
	case $opt in
		a)
			API="$OPTARG"
			;;
		d)
			DURATION="-d $OPTARG"
			;;
		f)
			VDSOTESTALL="${OPTARG}"
			;;
		t)
			TEST_TYPE="${OPTARG}"
			;;

		u)
			if [[ "$OPTARG" != '' ]]; then
				TEST_GIT_URL="$OPTARG"
			fi
			;;
		p)
			if [[ "$OPTARG" != '' ]]; then
				TEST_DIR="${OPTARG}"
			fi
			;;
		s)
			SKIP_INSTALL="${OPTARG}"
			;;
		v)
			TEST_PROG_VERSION="${OPTARG}"
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

install_vdso_tests() {
	dist=
	dist_name
	case "${dist}" in
		debian|ubuntu)
			pkgs="git build-essential libnuma-dev python3-dev"
			install_deps "${pkgs}" "${SKIP_INSTALL}"
			;;
		fedora|centos)
			pkgs="git-core make automake gcc gcc-c++ kernel-devel numactl-devel"
			install_deps "${pkgs}" "${SKIP_INSTALL}"
			;;
		# When build do not have package manager
		# Assume dependencies pre-installed
		*)
			echo "Unsupported distro: ${dist}! Package installation skipped!"
			;;
	esac
	git clone https://github.com/nathanlynch/vdsotest.git
	pushd vdsotest || exit
	./autogen.sh && ./configure && make && make install
	popd || exit
	rm -rf vdsotest
}

parse_output() {
    # Replace special chars wit space in results file
    sed -i -e 's/(/ /g' "${RESULT_LOG}"
    sed -i -e 's/)/ /g' "${RESULT_LOG}"
    sed -i -e 's/:/ /g' "${RESULT_LOG}"
    sed -i -e 's/,/ /g' "${RESULT_LOG}"
    # Parse each type of results
    grep -E "OK" "${RESULT_LOG}" | tee -a "${TEST_PASS_LOG}"
    awk '{for (i=1; i<NF-1; i++) printf $i "-"; print $i " " "pass"}' "${TEST_PASS_LOG}" 2>&1 | tee -a "${RESULT_FILE}"

    grep -E "FAIL" "${RESULT_LOG}" | tee -a "${TEST_FAIL_LOG}"
    awk '{for (i=1; i<NF-1; i++) printf $i "-"; print $i " " "fail"}' "${TEST_FAIL_LOG}" 2>&1 | tee -a "${RESULT_FILE}"

    grep -E "SKIP" "${RESULT_LOG}" | tee -a "${TEST_SKIP_LOG}"
    awk '{for (i=1; i<NF-1; i++) printf $i "-"; print $i " " "skip"}' "${TEST_SKIP_LOG}" 2>&1 | tee -a "${RESULT_FILE}"

    grep -E "nsec/call" "${RESULT_LOG}" | tee -a "${TEST_METRIC_LOG}"
    awk '{for (i=1; i<NF-2; i++) printf $i "-"; print $i " " "$NF-1" " " "$NF"}' "${TEST_METRIC_LOG}" 2>&1 | tee -a "${RESULT_FILE}"

    # Clean up
    rm -rf "${TMP_LOG}" "${RESULT_LOG}" "${TEST_PASS_LOG}" "${TEST_FAIL_LOG}" "${TEST_SKIP_LOG}"

}

run_test() {
	if [ "${VDSOTESTALL}" = "all" ]; then
		vdsotest-all -g -v 2>&1 | tee -a "${RESULT_LOG}"
	else
		vdsotest "${DURATION}" "${API}" "${TEST_TYPE}" -g -v 2>&1 | tee -a "${RESULT_LOG}"
	fi
	parse_output
}


! check_root && error_msg "This script must be run as root"
create_out_dir "${OUTPUT}"
	
# Install and run test
if [ "${SKIP_INSTALL}" = "true" ] || [ "${SKIP_INSTALL}" = "True" ]; then
	info_msg "Skip installing package dependency for ${TEST_PROG_VERSION}"
	which vdsotest || info_msg "Please install vdsotest"
else
	get_test_program "${TEST_GIT_URL}" "${TEST_DIR}" "${TEST_PROG_VERSION}" "${TEST_PROGRAM}"
	create_out_dir "${OUTPUT}"
        install_vdso_tests
fi
run_test
