#!/bin/bash

set -x

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
TEST_PROGRAM="mmtests"

usage() {
  echo "\
  Usage: $0 [-s] [-v <TEST_PROG_VERSION>] [-u <TEST_GIT_URL>] [-p <TEST_DIR>]
          [-c <MMTESTS_CONFIG_FILE>] [-r <MMTESTS_MAX_RETRIES>]
          [-i <MMTEST_ITERATIONS>]

  -v <TEST_PROG_VERSION>
    If this parameter is set, then the ${TEST_PROGRAM} suite is cloned. In
    particular, the version of the suite is set to the commit pointed to by the
    parameter. A simple choice for the value of the parameter is, e.g., HEAD.
    If, instead, the parameter is not set, then the suite present in TEST_DIR
    is used.

  -u <TEST_GIT_URL>
    If this parameter is set, then the ${TEST_PROGRAM} suite is cloned from the
    URL in TEST_GIT_URL. Otherwise it is cloned from the standard repository
    for the suite. Note that cloning is done only if TEST_PROG_VERSION is not
    empty.

  -p <TEST_DIR>
    If this parameter is set, then the ${TEST_PROGRAM} suite is cloned to or
    looked for in TEST_DIR. Otherwise it is cloned to $(pwd)/${TEST_PROGRAM}

  -s
    This flag disables benchmark installation and benchmark's
    dependencies installation.

  -c <MMTESTS_CONFIG_FILE>
    MMTests configuration file name that describes how the benchmarks should
    be configured and executed. Mandatory parameter. List of all config files
    can be found in <mmtests-root>/configs/ directory.
    For example, configs/config-db-sqlite-insert-small

  -r <MMTESTS_MAX_RETRIES>
    Maximum number of retries for the single benchmark's source file download.

  -i <MMTEST_ITERATIONS>
    The number of iterations to run the benchmark for."

  exit 1
}

while getopts "c:p:r:su:v:i:" opt; do
  case "${opt}" in
    c)
      if [[ ! "${OPTARG}" == config* ]]; then
        error_msg "Please specify correct MMTests configuration file."
        usage
      fi
      MMTESTS_CONFIG_FILE="${OPTARG}"
      ;;
    p)
      if [[ "$OPTARG" != '' ]]; then
        TEST_DIR="${OPTARG}"
      fi
      ;;
    r)
      MMTESTS_MAX_RETRIES="${OPTARG}"
      ;;
    s)
      SKIP_INSTALL=true
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
      MMTEST_ITERATIONS="${OPTARG}"
      ;;
    *)
      usage
      ;;
  esac
done

if [ -z "$MMTESTS_CONFIG_FILE" ]; then
  error_msg "Please specify MMTests configuration file."
  usage
fi

SKIP_INSTALL=${SKIP_INSTALL:-"false"}
TEST_PROG_VERSION=${TEST_PROG_VERSION:-"master"}
TEST_GIT_URL=https://github.com/gormanm/mmtests
TEST_DIR=${TEST_DIR:-"$(pwd)/${TEST_PROGRAM}"}
OUTPUT="${TEST_DIR}/output"
MMTESTS_MAX_RETRIES=${MMTESTS_MAX_RETRIES:-"3"}
MMTEST_ITERATIONS=${MMTEST_ITERATIONS:-"10"}
MMTEST_EXTR="${TEST_DIR}/bin/extract-mmtests.pl"

check_perl_module() {
  # Function to check if a Perl module is installed
  cpan -l | grep -q "$1"
}

install_perl_deps() {
  # List of Perl dependencies for MMTests
  declare -a perl_modules=("JSON" "Cpanel::JSON::XS" "List::BinarySearch")
  # Check each module and install if necessary
  for module in "${perl_modules[@]}"; do
    if ! check_perl_module "${module}"; then
      cpan -f -i "${module}"
    else
      echo "Perl module ${module} is already installed."
    fi
  done
  unset PERL_MM_USE_DEFAULT
}

install_system_deps() {
  # Install system-wide dependencies required for the benchmarks and MMTests framework.
  dist=
  dist_name
  case "${dist}" in
  debian|ubuntu)
    pkgs="build-essential wget perl git autoconf automake bc binutils-dev \
      btrfs-progs linux-cpupower expect gcc hdparm hwloc-nox libtool numactl \
      tcl time xfsprogs xfslibs-dev libopenmpi-dev jq"
    install_deps "${pkgs}" "${SKIP_INSTALL}"
    ;;
  fedora|centos)
    pkgs="git gcc make automake libtool wget perl autoconf bc binutils-devel \
      btrfs-progs kernel-tools expect hdparm hwloc libtool numactl tcl time \
      xfsprogs openmpi-devel"
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
  AUTO_PACKAGE_INSTALL=yes
  export AUTO_PACKAGE_INSTALL
  downloaded=0
  counter=0
  results_dir=$(basename "$MMTESTS_CONFIG_FILE")
  # Install benchmark according to the configuration file.
  while [ $downloaded -eq 0 ] && [ $counter -lt "$MMTESTS_MAX_RETRIES" ]; do
    ./run-mmtests.sh -b -n -c "${MMTESTS_CONFIG_FILE}" "${results_dir}" && downloaded=1
    counter=$((counter+1))
  done
}

run_test() {

  info_msg "Running ${MMTESTS_CONFIG_FILE} test..."
  # It's required to export MMTEST_ITERATIONS as it will be used by
  # run-mmtests.sh from the MMTests package.
  export MMTEST_ITERATIONS=${MMTEST_ITERATIONS}
  results_dir=$(basename "$MMTESTS_CONFIG_FILE")
  # Run benchmark according config file and with disabled monitoring.
  # Using nice to increase priority for the benchmark.
  nice -n -5 ./run-mmtests.sh -np -c "${MMTESTS_CONFIG_FILE}" "${results_dir}"
}

extract_json() {
  # Extract results data from available logs for each benchmark in JSON format.
  # JSON files will be available in mmtests root directory.
  jsons=()
  results_loc="work/log"
  log_dirs=()

  if [ ! -d "${results_loc}" ]; then
    echo "Results dir $results_loc does not exist."
    return 1
  fi
  # Find all log directories
  while IFS= read -r -d '' log_dir; do
      if [ -d "$log_dir" ]; then
          iter_dir=$(basename "$log_dir")
          if [[ "$iter_dir" =~ ^iter-([0-9]+)$ ]]; then
              log_dirs+=("${log_dir%/iter-*}")
          fi
      fi
  done < <(find "${results_loc}" -type d -print0)
  # Filter & sort directories
  mapfile -t logd < <(printf "%s\n" "${log_dirs[@]}" | sort -u)
  for log_dir in "${logd[@]}"; do
    # Find testname
    full_testname=$(echo "$log_dir" | cut -d '/' -f 3)
    # Remove useless text
    testname=${full_testname#config-}
    # Find benchmark names. It's possible when in single run several benchmarks used.
    benchmarks=()
    while IFS= read -r benchmark; do
      benchmarks+=("$benchmark")
    done < <(find "${log_dir}/iter-0" -type d | grep -E 'logs$' | grep -Eo 'iter-0/.+/logs' | cut -d '/' -f 2)
    # Iterate through found benchmark names to extract results
    for benchmark in "${benchmarks[@]}"; do
      # Build JSON file name
      # MARKERwords added intentionally, this allows to parse filename
      # easily in the future.
      results_json=BENCHMARK${benchmark}_CONFIG${testname}.json
      # Call parser
      ${MMTEST_EXTR} -d ${results_loc} -b "${benchmark}" -n "${full_testname}" --print-json > "${results_json}"
      # Add JSON file name to array
      jsons+=("${results_json}")
    done
  done
  # It's required to return of array separated by new line
  printf "%s\n" "${jsons[@]}"
}

collect_details() {
  # Collect benchmark run details
  MEMTOTAL_BYTES=$(free -b | grep Mem: | awk '{print $2}')
  NUMCPUS=$(grep -c '^processor' /proc/cpuinfo)
  NUMNODES=$(grep ^Node /proc/zoneinfo | awk '{print $2}' | wc -l)
  LLC_INDEX=$(find /sys/devices/system/cpu/ -type d -name "index*" | sed -e 's/.*index//' | sort -n | tail -1)
  NUMLLCS=$(grep . /sys/devices/system/cpu/cpu*/cache/index"$LLC_INDEX"/shared_cpu_map | awk -F : '{print $NF}' | wc -l)
  KERNEL_VERSION=$(uname -r)
  cat <<EOF
{
  "MEMTOTAL_BYTES": "${MEMTOTAL_BYTES:-}",
  "NUMCPUS": "${NUMCPUS:-}",
  "NUMNODES": "${NUMNODES:-}",
  "LLC_INDEX": "${LLC_INDEX:-}",
  "NUMLLCS": "${NUMLLCS:-}",
  "KERNEL_VERSION": "${KERNEL_VERSION:-}",
  "MMTEST_ITERATIONS": "${MMTEST_ITERATIONS:-}",
  "MMTESTS_CONFIG_FILE": "${MMTESTS_CONFIG_FILE:-}"
}
EOF
}

collect_results() {
  # Extract results data from available logs for each benchmark in JSON format.
  if output=$(extract_json); then
    mapfile -t jsons <<< "$output"
  else
    echo "extract_json failed."
    exit 1
  fi
  # Collect benchmark run details in JSON object.
  details=$(collect_details)
  # Dump details to temp file
  details_file=$(mktemp)
  echo "$details" > "$details_file"
  for json in "${jsons[@]}"; do
    # Create a temp file to hold the merged JSON
    merge_file=$(mktemp)
    # Merge details and results JSON
    jq -n \
        --argfile d "$details_file" \
        --argfile r "$json" \
        '{details: $d, results: $r}' > "$merge_file"
    # Replace results file
    mv "$merge_file" "${OUTPUT}"/"$json"
  done
}

! check_root && error_msg "Please run this script as root."

if [ "${SKIP_INSTALL}" = "true" ]; then
  info_msg "Installation skipped"
else
  # Install system-wide dependencies.
  install_system_deps
  # Install perl dependencies.
  install_perl_deps
  # Clone MMTests repository.
  get_test_program "${TEST_GIT_URL}" "${TEST_DIR}" "${TEST_PROG_VERSION}" "${TEST_PROGRAM}"
  # Install benchmark and Perl dependencies.
  prepare_system
fi

create_out_dir "${OUTPUT}"
pushd "${TEST_DIR}" || exit 1
run_test
collect_results
