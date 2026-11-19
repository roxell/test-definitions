#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2024 Linaro Ltd.

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
OUTPUT_FILE="${OUTPUT}/output.txt"
RESULT_FILE="${OUTPUT}/result.txt"
export RESULT_FILE
SKIP_INSTALL="true"
BOOT_TIMEOUT="300"

manager_time() {
    value=$(systemctl show --property="$1" --value)
    value=${value:-$2}
    case "${value}" in
        ""|*[!0-9]*)
            warn_msg "systemd has no time for $1: ${value}"
            return 1
            ;;
    esac
    echo "${value}"
}

add_time() {
    add_metric "systemd-analyze-$1" pass \
        "$(printf '%d.%03d' $(($2 / 1000000)) $(($2 % 1000000 / 1000)))" seconds
}

usage() {
    echo "\
    Usage: ${0} [-s True|False] [-t boot timeout in seconds]
    "
}

while getopts "hs:t:" opt; do
    case $opt in
        s)
            SKIP_INSTALL="${OPTARG}"
            ;;
        t)
            BOOT_TIMEOUT="${OPTARG}"
            ;;
        h|*)
            usage
            exit 1
            ;;
    esac
done

[ "${BOOT_TIMEOUT}" -gt 0 ] 2>/dev/null || { usage; exit 1; }

create_out_dir "${OUTPUT}"

pkgs="systemd"
install_deps "${pkgs}" "${SKIP_INSTALL}"

timeout "${BOOT_TIMEOUT}" systemctl is-system-running --wait
systemd-analyze > "${OUTPUT_FILE}"
analyze=$?
cat "${OUTPUT_FILE}"
[ "${analyze}" -eq 0 ] &&
    firmware=$(manager_time FirmwareTimestampMonotonic) &&
    loader=$(manager_time LoaderTimestampMonotonic) &&
    initrd=$(manager_time InitRDTimestampMonotonic) &&
    userspace=$(manager_time UserspaceTimestampMonotonic) &&
    finish=$(manager_time FinishTimestampMonotonic) &&
    security_start=$(manager_time SecurityStartTimestampMonotonic) &&
    soft_reboots=$(manager_time SoftRebootsCount 0)
exit_on_fail "systemd-analyze"

# Like systemd-analyze: after a soft reboot the times before userspace are
# from the previous boot, and a container (SecurityStartTimestamp 0) has none.
if [ "${soft_reboots}" -eq 0 ] && [ "${security_start}" -gt 0 ]; then
    if [ "${firmware}" -gt 0 ]; then
        add_time firmware $((firmware - loader))
    fi
    if [ "${loader}" -gt 0 ]; then
        add_time loader "${loader}"
    fi
    if [ "${initrd}" -gt 0 ]; then
        add_time kernel "${initrd}"
        add_time initrd $((userspace - initrd))
    else
        add_time kernel "${userspace}"
    fi
fi
add_time userspace $((finish - userspace))
