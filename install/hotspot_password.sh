#!/usr/bin/env bash
set -Eeuo pipefail

# Project NOMAD Raspberry Pi 5 Edition
# Secure Wi-Fi password input and validation.
# Does not modify system configuration.

read_hotspot_password() {
    local password confirm

    if [[ ! -t 0 ]]; then
        echo "ERROR: Interactive terminal required." >&2
        return 1
    fi

    while true; do
        read -r -s -p "Enter hotspot Wi-Fi password: " password
        echo

        if (( ${#password} < 12 || ${#password} > 63 )); then
            echo "Password must contain 12-63 characters."
            continue
        fi

        if [[ "$password" == *$'\n'* ||
              "$password" == *$'\r'* ||
              "$password" == *$'\t'* ||
              "$password" == *$' '* ]]; then
            echo "Password must not contain whitespace or control characters."
            continue
        fi

        if ! LC_ALL=C grep -qE '^[!-~]+$' <<< "$password"; then
            echo "Password must contain printable ASCII characters only."
            continue
        fi

        read -r -s -p "Confirm Wi-Fi password: " confirm
        echo

        if [[ "$password" != "$confirm" ]]; then
            echo "Passwords do not match."
            continue
        fi

        HOTSPOT_PASSWORD="$password"
        unset password confirm

        return 0
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "Project NOMAD Hotspot Password Validation"
    echo "========================================"

    read_hotspot_password

    echo
    echo "Password accepted."
    echo "Password length: ${#HOTSPOT_PASSWORD} characters."
    echo "No password was written to disk."

    unset HOTSPOT_PASSWORD
fi
