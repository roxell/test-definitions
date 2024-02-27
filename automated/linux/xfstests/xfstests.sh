#!/bin/sh

# shellcheck disable=SC1091
. ../../lib/sh-test-lib

OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
export RESULT_FILE
SKIP_INSTALL="false"

XFSTESTS_PATH="/opt/xfstests"

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
                    [-z <10G>]

         -d test device path
         -e scratch device path
         -f file system type 
         -m scratch mount path
	 -t test mount path
         -z size
" 1>&2
    exit 1
}

# test setup
test_setup() {
    export TEST_DEV="{TEST_DEV}"
    export SCRATCH_DEV="{SCRATCH_DEV}"
    export TEST_DIR="{TEST_DIR}"
    export SCRATCH_MNT="{SCRATCH_MNT}"
}

# run_xfstests ext4
run_xfstests() {
    FILESYSTEM=$1
    echo
    echo "run xfstests : ${FILESYSTEM}"
    test_setup
    ./check  -g "${FILESYSTEM}"/quick  -b
    exit_on_fail "run_xfstests"
}

# losetup "/dev/sdb"
losetup() {
    DEVICE=$1
    echo
    echo "Loop setup : ${DEVICE}"
    losetup -f "${DEVICE}" --show
    exit_on_fail "losetup"
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
    fallocate -l "${SIZE}" "${TEST_DIR}"
    exit_on_fail "fallocate-l-${SIZE}-${TEST_DIR}"
}

# Create fsgqa test users and groups
create_fsgqa_test_users_groups() {
    echo
    echo "Creating fsgqa test users and groups: "
    useradd -m fsgqa
    exit_on_fail "useradd-m-fsgq"
    useradd 123456-fsgqa
    exit_on_fail "useradd-123456-fsgqa"
    useradd fsgqa2
    exit_on_fail "useradd-fsgqa2"
    groupadd fsgqa
    exit_on_fail "groupadd-fsgqa"
}

while getopts "d:e:f:m:s:t:z:" arg; do
   case "$arg" in
     d) TEST_DEV="${OPTARG}";;
     e) SCRATCH_DEV="${OPTARG}" ;;
     f) FILESYSTEM="${OPTARG}" ;;
     m) SCRATCH_MNT="${OPTARG}" ;;
     t) TEST_DIR="${OPTARG}" ;;
     s) SKIP_INSTALL="${OPTARG}";;
     z) SIZE="${OPTARG}";;
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
    cd "${XFSTESTS_PATH}" || exit
else
    echo "xfstests not found"
fi

mkdir -p "{SCRATCH_MNT}"
mkdir -p "{TEST_DIR}"

create_fsgqa_test_users_groups

fallocate-manipulate-file-space "${TEST_DEV}" "${SIZE}"
fallocate-manipulate-file-space "${SCRATCH_DEV}" "${SIZE}"

format_disk_partitions "${TEST_DIR}" "${FILESYSTEM}"
format_disk_partitions "${SCRATCH_MNT}" "${FILESYSTEM}"

losetup "${DEVICE}"

run_xfstests "${FILESYSTEM}"
