#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Linaro Ltd.

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
export RESULT_FILE
TIMEOUT="120"

usage() {
    echo "\
    Usage: ${0} [-t <seconds>]

    -t  how long to wait for systemd to settle, default ${TIMEOUT}
    "
}

while getopts "ht:" opt; do
    case $opt in
        t)
            TIMEOUT="${OPTARG}"
            ;;
        h|*)
            usage
            exit 1
            ;;
    esac
done

create_out_dir "${OUTPUT}"

# Colours confuse the log parser, and a pager would hang the test.
SYSTEMD_COLORS=0
export SYSTEMD_COLORS

# No systemctl means systemd is not running this system. Installing it would
# not help, it still would not be pid 1. Skip instead.
if ! command -v systemctl > /dev/null; then
    echo "systemctl not found, systemd is not running this system"
    report_skip "systemd-boot-completed"
    report_skip "systemd-units-ok"
    exit 0
fi

# --wait blocks until the boot finishes. Both running and degraded mean it
# finished, degraded only says some unit failed on the way. That is what the
# unit count below is for, so do not fail the same problem twice here.
state="$(timeout "${TIMEOUT}" systemctl is-system-running --wait 2>/dev/null)"
rc="$?"

echo "systemd state: ${state:-unknown}"

case "${state}" in
    running|degraded)
        report_pass "systemd-boot-completed"
        ;;
    offline|unknown)
        report_skip "systemd-boot-completed"
        ;;
    *)
        # starting or initializing means we timed out. maintenance means it
        # dropped to a rescue shell. Neither is a finished boot.
        report_fail "systemd-boot-completed"
        ;;
esac

# 124 is what timeout returns when it had to kill the command. A boot that
# never finishes and a boot with a broken unit need different fixes.
if [ "${rc}" -eq 124 ]; then
    echo "systemd did not settle within ${TIMEOUT} seconds"
fi

systemctl status --failed --full --no-pager || true

broken="$(systemctl list-units --state=failed --no-legend --no-pager | wc -l)"
echo "units in a failed state: ${broken}"

# Keep the words fail and error out of the test case name. LAVA writes the
# name into /dev/kmsg, and the oeqa parselogs test reads dmesg and counts
# anything that looks like an error, including our own passing result.
if [ "${broken}" -eq 0 ]; then
    report_pass "systemd-units-ok"
else
    report_fail "systemd-units-ok"
fi
