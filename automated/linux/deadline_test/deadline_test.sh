#!/bin/sh -e
# This program is used to test the deadline scheduler
# (SCHED_DEADLINE tasks)

# shellcheck disable=SC1091
. ../../lib/sh-test-lib

OUTPUT="$(pwd)/output"
LOGFILE="${OUTPUT}/deadline_test"
RESULT_FILE="${OUTPUT}/result.txt"

INTERVAL="1000"
STEP="500"
THREADS="1"
BACKGROUND_CMD=""
ITERATIONS=1

usage() {
    echo "Usage: $0 [-i interval] [-s step] [-t threads] [-w background_cmd] [-I iterations]" 1>&2
    exit 1
}

while getopts ":i:s:t:w:I:" opt; do
    case "${opt}" in
        i) INTERVAL="${OPTARG}" ;;
        s) STEP="${OPTARG}" ;;
        t) THREADS="${OPTARG}" ;;
        w) BACKGROUND_CMD="${OPTARG}" ;;
        I) ITERATIONS="${OPTARG}" ;;
        *) usage ;;
    esac
done

! check_root && error_msg "Please run this script as root."
create_out_dir "${OUTPUT}"

if [ "${THREADS}" -eq "0" ]; then
    THREADS=$(nproc)
fi

# Run cyclicdeadline.
if ! binary=$(command -v deadline_test); then
    error_msg "No binary called deadline_test"
fi

background_process_start bgcmd --cmd "${BACKGROUND_CMD}"

counter=0
while [ ${counter} -lt ${ITERATIONS} ]; do
    "${binary}" -i "${INTERVAL}" -s "${STEP}" -t "${THREADS}" \
        --json="${LOGFILE}-${counter}.json"
    counter=$((counter + 1))
done

background_process_stop bgcmd

# Parse test log.
counter=0
while [ ${counter} -lt ${ITERATIONS} ]; do
../../lib/parse_rt_tests_results.py cyclicdeadline "${LOGFILE}-${counter}.json" \
        | tee /tmp/output

    if [ ${ITERATIONS} -ne 1 ]; then
        sed -i "s|^|iteration-${counter}-|g" /tmp/output
    fi
    cat /tmp/output | tee -a "${RESULT_FILE}"
    counter=$((counter + 1))
done
