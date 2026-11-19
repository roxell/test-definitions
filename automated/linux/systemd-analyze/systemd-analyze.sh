#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2024 Linaro Ltd.

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
OUTPUT_FILE="${OUTPUT}/output.txt"
RESULT_FILE="${OUTPUT}/result.txt"
SKIP_INSTALL="true"
BOOT_TIMEOUT="300"

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
exit_on_fail "systemd-analyze"
cat "${OUTPUT_FILE}"

head -1 "${OUTPUT_FILE}" | grep -oP '\d+\.\d+s \(\w+\)' | while read -r row; do
    seconds=$(echo "${row}"| awk -F ' ' '{print $1}'|sed -e 's|s$||g')
    what=$(echo "${row}"| awk -F ' ' '{print $2}'|sed -e 's|^(||g'|sed -e 's|)$||g')
    echo "systemd-analyze-${what} pass ${seconds} seconds" | tee -a "${RESULT_FILE}"
done
