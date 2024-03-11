#!/bin/sh
# Improved Shell Script for Running XFS Tests

# Load required libraries

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

  -d <device>     Specify the test device path (default: /dev/loop0)
  -e <device>     Specify the scratch device path (default: /dev/loop1)
  -f <filesystem> Set the filesystem type (default: ext4)
  -m <path>       Set the scratch mount path (default: /mnt/scratch)
  -t <path>       Set the test mount path (default: /mnt/test)
  -s <bool>       Skip package installation (default: false)
  -z <size>       Set the test and scratch size (default: 5G for test, 8G for scratch)
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

# Needs RUNTESTS, SKIPTESTS, MKFS_OPTS, FSCK_OPTS, CHECK_OPTS and REPORT_PASS, REPORT_FAIL, KNOWN_ISSUE
function check_tests()
{
    # backup original OUTPUTFILE, each XFSTEST will use different OUTPUTFILE
    BAK_OUTPUTFILE=${OUTPUTFILE}
    for XFSTEST in $RUNTESTS; do
        ret=0
        # Skip tests that are failing, for now.  Some need fixing, others expected
        if echo $SKIPTESTS | grep -qw $XFSTEST; then
            echo "Skipping test $XFSTEST due to known failure"
            continue
        fi
        if echo $SKIPTESTS | grep -q "\([^/]\|^\)[[:digit:]]\{3\}"; then
            # We have old style test seq number in SKIPTESTS, e.g. 300
            # filter all tests with the same seq number, no matter it's
            # generic/300 or xfs/300
            if echo $SKIPTESTS | grep -q "\([^/]\|^\)$(basename $XFSTEST)"; then
                echo "Skipping test $XFSTEST due to known failure"
                continue
            fi
        fi
        if [ "$FSTYPE" == "btrfs" ] && grep -H -m 1 dmflakey tests/$XFSTEST ; then
            echo "Skipping dmfalkey test $XFSTEST on $FSTYPE due to unstable"
            continue
        fi

        # Construct XFSTEST_LOGNAME, used for submitting logs to beaker to avoid
        # overwriting test logs with the same seq number under different dirs.
        # e.g. if both generic/300 and ext4/300 fail, log file to be submitted
        # are both 300.full/300.out.bad
        # Rename log file by adding dir name prefix, so results/generic/300.full
        # will be results/generic/generic-300.full, results/ext4/300.full will be
        # results/ext4/ext4-300.full
        XFSTEST_LOGNAME=$(dirname $XFSTEST)/${XFSTEST/\//-}
        OUTPUTFILE="results/${XFSTEST_LOGNAME}.log"
        mkdir -p $(dirname $OUTPUTFILE)
        echo "Running test $XFSTEST"
        if test -f tests/$XFSTEST; then
            xlog head -n 10 tests/$XFSTEST
        else
            echo "The test $XFSTEST does not seem to exist."
            continue
        fi
        # Clear the dmesg ring buffer, save dmesg for each test separately
        dmesg -c >/dev/null
        echo "./checking $XFSTEST" > /dev/kmsg
        MOUNT_OPTIONS="$MOUNT_OPTS" MKFS_OPTIONS="$MKFS_OPTS" xlog ./check $CHECK_OPTS $XFSTEST
        ret=$?
        dmesgfile="$XFSTEST.dmesg.log"
        dmesg > results/"${dmesgfile}"
        # Clear the dmesg ring buffer to avoid rstrnt-report-log also report
        # the same failure that xfstests _check_dmesg does.
        dmesg -c >/dev/null

        false_alarm=0
        if test $ret -ne 0; then
            rstrnt-report-log -l results/$XFSTEST_LOGNAME.log
            if [ -f results/$XFSTEST.full ]; then
                cp results/$XFSTEST.full results/$XFSTEST_LOGNAME.full
                rstrnt-report-log -l results/$XFSTEST_LOGNAME.full
            fi
            if [ -f results/$XFSTEST.out.bad ]; then
                cp results/$XFSTEST.out.bad results/$XFSTEST_LOGNAME.out.bad
                rstrnt-report-log -l results/$XFSTEST_LOGNAME.out.bad
                # Gather the full diff
                diff -u <(tr '`' "'" < tests/$XFSTEST.out) results/$XFSTEST.out.bad  > results/$XFSTEST_LOGNAME.out.bad.diff
                rstrnt-report-log -l results/$XFSTEST_LOGNAME.out.bad.diff
                sed -n '3,$ p' results/$XFSTEST_LOGNAME.out.bad.diff | grep "^+.*No space left on device" && false_alarm=1
                sed -n '3,$ p' results/$XFSTEST_LOGNAME.out.bad.diff | grep "^+.*Input/output error" && false_alarm=1
                sed -n '3,$ p' results/$XFSTEST_LOGNAME.out.bad.diff | grep "^+.*I/O error" && false_alarm=1
                sed -n '3,$ p' results/$XFSTEST_LOGNAME.out.bad.diff | grep "^+.*not supported" && false_alarm=1
            fi
            if [ -f results/$dmesgfile ]; then
                cp results/$dmesgfile results/$XFSTEST_LOGNAME.dmesg.log
                rstrnt-report-log -l results/$XFSTEST_LOGNAME.dmesg.log
                grep "possible circular locking dependency detected" results/$XFSTEST_LOGNAME.dmesg.log &&
                false_alarm=1
                grep "MAX_LOCKDEP_ENTRIES too low" results/$XFSTEST_LOGNAME.dmesg.log &&
                false_alarm=1
            fi
            if [ $false_alarm -eq 0 ] ; then
                ret=1
                rstrnt-report-result $XFSTEST FAIL 0
            fi
            # Work around, so that loop device bug does not interrupt the test,
            # might be nice to do the same with the dm device release bug
            release_loops
        elif test "$REPORT_PASS" == "1"; then
            TESTTIME=`grep -w ^$XFSTEST results/check.time | awk '{print $2}'`
            if [ -f results/$XFSTEST.notrun ]; then
                XFSTEST="${XFSTEST}[notrun]"
            fi
            rstrnt-report-result $XFSTEST PASS $TESTTIME
        fi
    done
    OUTPUTFILE=${BAK_OUTPUTFILE}
}

# Needs SKIPTESTS, RUNTESTS,
function check()
{
    local groups="${CHECK_GROUPS:-auto}"

    # And go!
    pushd /opt/xfstests/

    # Run all "auto" tests, excluding dmapi if FSTYPE is xfs
    # If FSTYPE is not xfs, -x dmapi would cause check to generate empty $RUNTESTS list with newer xfstests version
    if [ -z "$RUNTESTS" ]; then
        if [ "$FSTYPE" == "xfs" ]; then
            ./check -n $CHECK_OPTS -g $groups -x dmapi | grep -E "^$FSTYPE/|^generic/|^shared/|^[[:digit:]]{3}$" >alltests.log
        else
            ./check -n $CHECK_OPTS -g $groups | grep -E "^$FSTYPE/|^generic/|^shared/|^[[:digit:]]{3}$" >alltests.log
        fi
    else
        echo $RUNTESTS > alltests.log
    fi
    rstrnt-report-log -l alltests.log
    RUNTESTS=`cat alltests.log`
    if [ -z "$RUNTESTS" ]; then
        report RUNTESTS FAIL 0
        popd
        return 1
    fi
    echo "got RUNTESTS" > /dev/kmsg

    for ((n=0;n<$LOOP;n++));do
        check_tests
    done

    # Loop until a fail is detected if LOOP=0
    if test $LOOP -eq 0; then
        while check_tests; do :;done
    fi
    popd
    return 0
}

function run_full()
{
    # Just run the default preset function
    preset_full
    for FSTYPE in $FSTYPES; do
        # The variable BLKSIZES was set in preset_full
        # preset_full function
        # setup_blksize will handle this case properly and it won't
        # modify MKFS_OPTS based on this
        for BLKSIZE in $BLKSIZES; do
            export BLKSIZE
            # Now to the full fs-dependent setup
            setup_full
            # Now print the test info
            # It should print all the test variables
            system_info
            # And now, just run the test
            check
        done
    done
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
