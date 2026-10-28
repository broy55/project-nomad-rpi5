#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/hotspot_manifest.sh"

usage() {
    echo "Usage: $0 {install|rollback|status} --root TEST_DIRECTORY"
}

[[ $# -eq 3 && "$2" == "--root" ]] || {
    usage
    exit 1
}

ACTION="$1"
ROOT="$(realpath -e -- "$3")"

# Safety: this development component must never target the real root.
[[ "$ROOT" != "/" ]] || {
    echo "ERROR: Live filesystem operations are disabled."
    exit 1
}

# Require a dedicated test-root marker.
[[ -f "$ROOT/.nomad-hotspot-test-root" ]] || {
    echo "ERROR: Not a marked test filesystem."
    exit 1
}

JOURNAL="$ROOT/.nomad-hotspot-transaction"
PREVIEW_DIR="$SCRIPT_DIR/hotspot-preview"

case "$ACTION" in
    install)
        [[ ! -e "$JOURNAL" ]] || {
            echo "ERROR: Existing transaction requires recovery."
            exit 1
        }

        bash "$SCRIPT_DIR/plan_hotspot_install.sh" --root "$ROOT"

        # Record the complete intended file set before installation.
        printf '%s\n' "${HOTSPOT_DESTINATIONS[@]}" > "$JOURNAL"

        for i in "${!HOTSPOT_SOURCES[@]}"; do
            source_file="$PREVIEW_DIR/${HOTSPOT_SOURCES[$i]}"
            destination="$ROOT${HOTSPOT_DESTINATIONS[$i]}"

            mkdir -p -- "$(dirname "$destination")"

            # Exclusive creation: never overwrite an existing target.
            (
                set -C
                : > "$destination"
            )

            chmod "${HOTSPOT_MODES[$i]}" "$destination"
            cat -- "$source_file" > "$destination"

            echo "INSTALLED: ${HOTSPOT_DESTINATIONS[$i]}"
        done

        echo "Transaction files installed."
        echo "Journal retained for simulated recovery testing."
        ;;

    rollback)
        [[ -f "$JOURNAL" ]] || {
            echo "No transaction journal found."
            exit 0
        }

        mapfile -t entries < "$JOURNAL"

        for ((i=${#entries[@]}-1; i>=0; i--)); do
            destination="${entries[$i]}"

            # Only permit paths declared in the manifest.
            allowed=false
            for manifest_path in "${HOTSPOT_DESTINATIONS[@]}"; do
                if [[ "$destination" == "$manifest_path" ]]; then
                    allowed=true
                    break
                fi
            done

            [[ "$allowed" == true ]] || {
                echo "ERROR: Unexpected journal entry."
                exit 1
            }

            rm -f -- "$ROOT$destination"
            echo "ROLLED BACK: $destination"
        done

        rm -f -- "$JOURNAL"
        echo "Rollback completed."
        ;;

    status)
        if [[ -f "$JOURNAL" ]]; then
            echo "Transaction journal exists."
            cat "$JOURNAL"
        else
            echo "No transaction journal found."
        fi
        ;;

    *)
        usage
        exit 1
        ;;
esac
