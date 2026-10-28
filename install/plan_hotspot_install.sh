#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIEW_DIR="$SCRIPT_DIR/hotspot-preview"

# Optional simulated filesystem root for testing.
# Default remains the real filesystem, inspection only.
ROOT="/"

if [[ "${1:-}" == "--root" ]]; then
    if [[ $# -ne 2 || ! -d "$2" ]]; then
        echo "Usage: $0 [--root EXISTING_DIRECTORY]" >&2
        exit 1
    fi

    ROOT="$(realpath "$2")"
elif [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--root EXISTING_DIRECTORY]" >&2
    exit 1
fi

echo "Project NOMAD Raspberry Pi 5"
echo "Hotspot Installation Plan"
echo "==========================="
echo

if [[ ! -d "$PREVIEW_DIR" ]]; then
    echo "ERROR: Preview directory missing."
    echo "Run setup_hotspot.sh --prepare first."
    exit 1
fi

# Load the shared hotspot file manifest.
source "$SCRIPT_DIR/hotspot_manifest.sh"

conflicts=0

for i in "${!HOTSPOT_SOURCES[@]}"; do
    source_file="$PREVIEW_DIR/${HOTSPOT_SOURCES[$i]}"
    destination="${HOTSPOT_DESTINATIONS[$i]}"

    if [[ "$ROOT" != "/" ]]; then
        destination="${ROOT}${destination}"
    fi

    echo "SOURCE: $source_file"
    echo "TARGET: $destination"

    if [[ ! -f "$source_file" ]]; then
        echo "STATUS: MISSING SOURCE"
        ((conflicts+=1))
    elif [[ -e "$destination" || -L "$destination" ]]; then
        echo "STATUS: CONFLICT — target already exists"
        ((conflicts+=1))
    else
        echo "STATUS: AVAILABLE"
    fi

    echo
done

echo "===== INSTALLATION READINESS ====="

if (( conflicts > 0 )); then
    echo "BLOCKED: $conflicts missing source(s) or existing target(s)."
    echo "No files were installed or modified."
    exit 2
fi

echo "All seven file destinations are available."
echo "Additional service and network validation is still required."
echo "No files were installed or modified."
