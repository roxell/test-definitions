#!/bin/bash

set -x

# shellcheck disable=SC1091
. ../../lib/sh-test-lib

OUTPUT="$(pwd)/output"
TEST_PROGRAM="mmtests"
TEST_PROG_VERSION=
TEST_GIT_URL=https://github.com/gormanm/mmtests
TEST_DIR=${TEST_DIR:-"$(pwd)/${TEST_PROGRAM}"}
SKIP_INSTALL=${SKIP_INSTALL:-"false"}
MMTESTS_MAX_RETRIES=${MMTESTS_MAX_RETRIES:-"3"}
MMTESTS_TYPE_NAME=
MMTESTS_CONFIG_FILE=
MMTEST_ITERATIONS=${MMTEST_ITERATIONS:-"10"}

# DBENCH specific variables
declare -A altreport_mappings=( ["dbench4"]="tput latency opslatency")
declare -A env_variable_mappings=( ["dbench4"]="DBENCH" )

usage() {
	echo "\
	Usage: $0 [-s <true|false>]
		[-v <TEST_PROG_VERSION>]
		[-u <TEST_GIT_URL>]
		[-p <TEST_DIR>]
		[-c <MMTESTS_CONFIG_FILE>]
		[-t <MMTESTS_TYPE_NAME>]
		[-r <MMTESTS_MAX_RETRIES>]
		[-i <MMTEST_ITERATIONS>]

	<TEST_PROG_VERSION>:
	If this parameter is set, then the ${TEST_PROGRAM} suite is cloned. In
	particular, the version of the suite is set to the commit
	pointed to by the parameter. A simple choice for the value of
	the parameter is, e.g., HEAD. If, instead, the parameter is
	not set, then the suite present in TEST_DIR is used.

	<TEST_GIT_URL>:
	If this parameter is set, then the ${TEST_PROGRAM} suite is cloned
	from the URL in TEST_GIT_URL. Otherwise it is cloned from the
	standard repository for the suite. Note that cloning is done
	only if TEST_PROG_VERSION is not empty

	<TEST_DIR>:
	If this parameter is set, then the ${TEST_PROGRAM} suite is cloned to or
	looked for in TEST_DIR. Otherwise it is cloned to $(pwd)/${TEST_PROGRAM}

	<SKIP_INSTALL>:
	This flag controls two things: benchmark installation and benchmark's
	dependencies installation.
	default: false

	<MMTESTS_CONFIG_FILE>:
	MMMTests configuration file that describes how the benchmarks should be
	configured and executed.

	<MMTESTS_TYPE_NAME>:
	MMTests test type, e.g. sysbenchcpu, iozone, sqlite, etc.

	<MMTESTS_MAX_RETRIES>:
	Maximum number of retries for the single benchmark's source file download

	<MMTEST_ITERATIONS>:
	The number of iterations to run the benchmark for."

	exit 1
}

while getopts "c:p:r:s:t:u:v:i:" opt; do
	case "${opt}" in
		c)
			MMTESTS_CONFIG_FILE="${OPTARG}"
			;;
		p)
			if [[ "$OPTARG" != '' ]]; then
				TEST_DIR="$OPTARG"
			fi
			;;
		r)
			MMTESTS_MAX_RETRIES="${OPTARG}"
			;;
		s)
			SKIP_INSTALL="${OPTARG}"
			;;
		t)
			MMTESTS_TYPE_NAME="${OPTARG}"
			;;
		u)
			if [[ "$OPTARG" != '' ]]; then
			TEST_GIT_URL="${OPTARG}"
			fi
			;;
		v)
			TEST_PROG_VERSION="${OPTARG}"
			;;
		i)
			MMTESTS_ITERATIONS="${OPTARG}"
			;;
		*)
			usage
			;;
	esac
done

install() {
	dist=
	dist_name
	case "${dist}" in
	debian|ubuntu)
			pkgs="build-essential wget perl git autoconf automake \
					bc binutils-dev btrfs-progs linux-cpupower expect \
					gcc hdparm hwloc-nox libtool numactl tcl time \
					xfsprogs xfslibs-dev libopenmpi-dev jq"
			install_deps "${pkgs}" "${SKIP_INSTALL}"
		;;
	fedora|centos)
		pkgs="git gcc make automake libtool wget perl autoconf \
					bc binutils-devel btrfs-progs kernel-tools expect \
					hdparm hwloc libtool numactl tcl time xfsprogs \
					openmpi-devel"
			install_deps "${pkgs}" "${SKIP_INSTALL}"
		;;
	oe-rpb)
		# Assume all dependent packages are already installed.
		;;
	*)
		warn_msg "Unsupported distro: ${dist}! Package installation skipped!"
		;;
	esac
}

prepare_system() {
	# Install additional Perl dependencies.
	pushd "${TEST_DIR}" || exit
	PERL_MM_USE_DEFAULT=1
	export PERL_MM_USE_DEFAULT
	cpan -f -i JSON Cpanel::JSON::XS List::BinarySearch
	AUTO_PACKAGE_INSTALL=yes
	export AUTO_PACKAGE_INSTALL
	DOWNLOADED=0
	COUNTER=0
	# Install benchmark according to the configuration file.
	while [ $DOWNLOADED -eq 0 ] && [ $COUNTER -lt "$MMTESTS_MAX_RETRIES" ]; do
		./run-mmtests.sh -b --no-monitor --config "${MMTESTS_CONFIG_FILE}" benchmark && DOWNLOADED=1
		COUNTER=$((COUNTER+1))
	done
	popd || exit
}

run_test() {
	pushd "${TEST_DIR}" || exit
  info_msg "Running ${MMTESTS_TYPE_NAME} test..."
  # Run benchmark according config file and with disabled monitoring.
  # Results will be stored in work/log/benchmark directory.
	MMTEST_ITERATIONS=${MMTESTS_ITERATIONS} ./run-mmtests.sh --no-monitor --config "${MMTESTS_CONFIG_FILE}" benchmark

	MEMTOTAL_BYTES=$(free -b | grep Mem: | awk '{print $2}')
	export MEMTOTAL_BYTES
	NUMCPUS=$(grep -c '^processor' /proc/cpuinfo)
	export NUMCPUS
	NUMNODES=$(grep ^Node /proc/zoneinfo | awk '{print $2}' | sort | uniq | wc -l)
	export NUMNODES
	LLC_INDEX=$(find /sys/devices/system/cpu/ -type d -name "index*" | sed -e 's/.*index//' | sort -n | tail -1)
	export LLC_INDEX
	NUMLLCS=$(grep . /sys/devices/system/cpu/cpu*/cache/index"$LLC_INDEX"/shared_cpu_map | awk -F : '{print $NF}' | sort | uniq | wc -l)
	export NUMLLCS

	chmod u+x ./"${MMTESTS_CONFIG_FILE}"
	eval 'source ./${MMTESTS_CONFIG_FILE}'
	# Extract results data from available logs for each benchmark in JSON format.
	# JSON files will be available in mmtests root directory.

	# Note: benchmark name is not always equal to benchmark name from config file.
	if [ "${MMTESTS_TYPE_NAME}" != "${MMTESTS}" ]; then
		EXTRACT_NAMES="${MMTESTS}"
	else
		EXTRACT_NAMES="${MMTESTS_TYPE_NAME}"
	fi

	echo "test(s) to extract: ${EXTRACT_NAMES}"
	for benchmark_name in ${EXTRACT_NAMES}; do
		echo "results for: $benchmark_name"
		./bin/extract-mmtests.pl -d work/log/ -b "${benchmark_name}" -n benchmark --print-json >> "../${MMTESTS_TYPE_NAME}_${benchmark_name}.json"

		altreports=${altreport_mappings[${benchmark_name}]}
		for altreport in ${altreports}; do
			./bin/extract-mmtests.pl -d work/log/ -b "${benchmark_name}" -n benchmark\
			-a "${altreport}" --print-json > "../${MMTESTS_TYPE_NAME}_${benchmark_name}${altreport}.json"
		done
	done

	env_variables_prefix=${env_variable_mappings[${MMTESTS_TYPE_NAME}]}
	if [ -z "$env_variables_prefix" ]; then
		env_variables_prefix=${MMTESTS_TYPE_NAME^^}
	fi
	
	vars=""
	eval 'vars=${!'"$env_variables_prefix"'*}'
	for variable in ${vars}; do
		mykey=CONFIG_${variable}
		mykey=${mykey//_/-}
		myvalue=${!variable}
		echo "$mykey":"$myvalue"
		tmp=$(mktemp)
		jq -c --arg key "$mykey" --arg value "$myvalue" '. += {($key):$value}' ../"${MMTESTS_TYPE_NAME}"_"${benchmark_name}".json > "$tmp" && mv "$tmp" ../"${MMTESTS_TYPE_NAME}"_"${benchmark_name}".json
	done

	chmod a+r "../$MMTESTS_TYPE_NAME"*".json"

	popd || exit
}

! check_root && error_msg "Please run this script as root."

# Test installation.
if [ "${SKIP_INSTALL}" = "true" ] || [ "${SKIP_INSTALL}" = "True" ]; then
	info_msg "${MMTESTS_TYPE_NAME} installation skipped"
else
	install
fi
# Clone MMTests repository.
get_test_program "${TEST_GIT_URL}" "${TEST_DIR}" "${TEST_PROG_VERSION}" "${TEST_PROGRAM}"

create_out_dir "${OUTPUT}"
prepare_system
run_test
