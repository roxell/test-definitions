#!/bin/sh
# Shell Script for Running XFS Tests

set -x
# Load required libraries

# shellcheck disable=SC1091
. ../../lib/sh-test-lib

OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
export RESULT_FILE

RESULT_LOG="${OUTPUT}/logs.txt"
RESULT_PASS="${OUTPUT}/pass.txt"
RESULT_FAIL="${OUTPUT}/fail.txt"
RESULT_SKIP="${OUTPUT}/skip.txt"

SKIP_INSTALL="false"

XFSTESTS_PATH="/opt/xfstests"

TEST_IMG=test.img
SCRATCH_IMG=scratch.img
TEST_DEV=/dev/loop0
SCRATCH_DEV=/dev/loop1
TEST_DIR=/mnt/test
SCRATCH_MNT=/mnt/scratch
FILESYSTEM="ext4"
T_SIZE="5G"
S_SIZE="8G"

# usage
usage() {
    echo "Usage: $0 [-d </dev/sdb>] [-e </dev/loop0>]
                    [-f <ext4>] [-m </mnt/scratch>]
                    [-t </mnt/test>] [-s <true|false>]
                    [-x <10G>] [-z <10G>]

  -d <device>     Specify the test device path (default: /dev/loop0)
  -e <device>     Specify the scratch device path (default: /dev/loop1)
  -f <filesystem> Set the filesystem type (default: ext4)
  -m <path>       Set the scratch mount path (default: /mnt/scratch)
  -t <path>       Set the test mount path (default: /mnt/test)
  -s <true>       Skip package installation (default: false)
  -x <size>       Set the test and scratch size (default: 5G for test, 8G for scratch)
  -z <size>       Set the test and scratch size (default: 5G for test, 8G for scratch)
  " 1>&2
    exit 1
}

results_parser() {
   OUTPUT="$1"

   # Parse pass test cases
   find results/ -type f -name "*.full" -print0 | while IFS= read -r -d $'\0' file; do
    echo "${file#results/}" | sed -e "s/\//-/g" -e "s/.full$//g" -e "s/$/ pass/"
   done >> "${RESULT_PASS}"
   
   # Parse fail test cases   
   find results/ -type f -name "*.out.bad" -print0 | while IFS= read -r -d $'\0' file; do
    echo "${file#results/}" | sed -e "s/\//-/g" -e "s/.out.bad$//g" -e "s/$/ fail/"
   done >> "${RESULT_FAIL}"

   # Parse skip test cases
   find results/ -type f -name "*.notrun" -print0 | while IFS= read -r -d $'\0' file; do
    echo "${file#results/}" | sed -e "s/\//-/g" -e "s/.notrun$//g" -e "s/$/ skip/"
   done >> "${RESULT_SKIP}"
   
   cat "${RESULT_PASS}" "${RESULT_FAIL}" "${RESULT_SKIP}" 2>&1 | tee -a "${RESULT_FILE}"
}

# test setup
test_setup() {
    export TEST_IMG="${TEST_IMG}"
    export SCRATCH_IMG="${SCRATCH_IMG}"
    export TEST_DEV="${TEST_DEV}"
    export SCRATCH_DEV="${SCRATCH_DEV}"
    export TEST_DIR="${TEST_DIR}"
    export SCRATCH_MNT="${SCRATCH_MNT}"
    export FILESYSTEM="${FILESYSTEM}"
}

# run_xfstests ext4
run_xfstests() {
    FILESYSTEM=$1
    echo
    echo "run xfstests : ${FILESYSTEM}"
    test_setup
    if [ ""${FILESYSTEM}"" == "xfs" ]; then
        ./check -g ${FILESYSTEM}/quick -x dmapi 2>&1 | tee -a "${RESULT_LOG}"
    elif [ ""${FILESYSTEM}"" == "ext2" ]; then
        ./check -g generic -R xunit 2>&1 | tee -a "${RESULT_LOG}"
    elif [ ""${FILESYSTEM}"" == "ext3" ]; then
        ./check -g generic -R xunit  2>&1 | tee -a "${RESULT_LOG}"
    else
	    #TODO
	    # Run on 
#        ./check -g ${FILESYSTEM}/quick -R xunit 2>&1 | tee -a "${RESULT_LOG}"
        ./check -R xunit 2>&1 | tee -a "${RESULT_LOG}"
    fi
    
    #TODO
    echo "====================="
    cat "${RESULT_LOG}"
    echo "====================="
}


# losetup "/dev/sdb"
losetup() {
    DEVICE=$1
    echo
    echo "Loop setup : ${DEVICE}"
    LOOP_DEV='losetup -f "${DEVICE}" --show'
    return "${LOOP_DEV}"
}

# format_disk_partitions "/dev/sdb" "ext4"
format_disk_partitions() {
    DEVICE=$1
    FILESYSTEM=$2
    echo
    echo "Format disk partitions of: ${DEVICE}"
    format_partitions "${DEVICE}" "${FILESYSTEM}"
    exit_on_fail "format-disk-partitions"
}

# fallocate - manipulate file space
# fallocate-manipulate-file-space "/test-dir" "5G"
fallocate_manipulate_file_space() {
    TEST_DIR=$1
    SIZE=$2
    echo
    echo "fallocate - manipulate file space"
    fallocate -l "${SIZE}" "${TEST_DIR}" --show
    exit_on_fail "fallocate-l-${SIZE}-${TEST_DIR}"
}

# Create fsgqa test users and groups
create_fsgqa_test_users_groups() {
    echo
    echo "Creating fsgqa test users and groups: "
    useradd -m fsgqa
    report_fail "useradd-m-fsgq"
    useradd 123456-fsgqa
    report_fail "useradd-123456-fsgqa"
    useradd fsgqa2
    report_fail "useradd-fsgqa2"
    groupadd fsgqa
    report_fail "groupadd-fsgqa"
}

while getopts "d:e:f:m:s:t:x:z:" arg; do
   case "$arg" in
     d) TEST_DEV="${OPTARG}";;
     e) SCRATCH_DEV="${OPTARG}" ;;
     f) FILESYSTEM="${OPTARG}" ;;
     m) SCRATCH_MNT="${OPTARG}" ;;
     t) TEST_DIR="${OPTARG}" ;;
     s) SKIP_INSTALL="${OPTARG}";;
     x) T_SIZE="${OPTARG}";;
     z) S_SIZE="${OPTARG}";;
     *) usage ;;
  esac
done

# Test run.
[ -b "${DEVICE}" ] || error_msg "Please specify a block device with '-d'"
! check_root && error_msg "You need to be root to run this script."
create_out_dir "${OUTPUT}"

info_msg "About to run fdisk tests ..."
info_msg "Output directory: ${OUTPUT}"

pkgs="acl attr automake bc dbench dump e2fsprogs fio gawk  gcc git indent libacl1-dev libaio-dev libcap-dev libgdbm-dev libtool libtool-bin liburing-dev libuuid1 lvm2 make psmisc python3 quota sed uuid-dev uuid-runtime xfsprogs linux-headers-$(uname -r) sqlite3 libgdbm-compat-dev"
install_deps "${pkgs}" "${SKIP_INSTALL}"

if [ -d "${XFSTESTS_PATH}" ]; then
    echo "xfstests found on rootfs"
    # shellcheck disable=SC2164
    pushd "${XFSTESTS_PATH}" || exit 1
else
    echo "xfstests not found"
    error_fatal "xfstests-not-found"
fi

mkdir -p "${TEST_DIR}"
mkdir -p "${SCRATCH_MNT}"

create_fsgqa_test_users_groups

fallocate-manipulate-file-space "${TEST_IMG}" "${T_SIZE}"
fallocate-manipulate-file-space "${SCRATCH_IMG}" "${S_SIZE}"

format_disk_partitions "${TEST_IMG}" "${FILESYSTEM}"
format_disk_partitions "${SCRATCH_IMG}" "${FILESYSTEM}"

TEST_DEV='losetup "${TEST_IMG}"'
SCRATCH_DEV='losetup "${SCRATCH_IMG}"'

# Run xfstests
run_xfstests "${FILESYSTEM}"

# Parse xfstests results
parse_results "${OUTPUT}"
