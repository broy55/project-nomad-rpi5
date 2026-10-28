#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIEW_DIR="$SCRIPT_DIR/hotspot-preview"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

# Load shared configuration manifest.
source "$SCRIPT_DIR/hotspot_manifest.sh"

# Track files created by this transaction.
created_files=()

rollback() {
  echo
  echo "===== AUTOMATIC ROLLBACK ====="

  for ((i=${#created_files[@]}-1; i>=0; i--)); do
    file="${created_files[$i]}"
    rm -f -- "$file"
    echo "ROLLED BACK: ${file#"$TEST_ROOT"}"
  done

  created_files=()
}

echo "===== SIMULATED PREFLIGHT ====="
bash "$SCRIPT_DIR/plan_hotspot_install.sh" --root "$TEST_ROOT"

echo
echo "===== SIMULATED INSTALLATION ====="

# Simulate a failure after installing three files.
for i in "${!HOTSPOT_SOURCES[@]}"; do
  if (( i == 3 )); then
    echo "SIMULATED FAILURE: Installation interrupted."
    rollback
    break
  fi

  source_file="$PREVIEW_DIR/${HOTSPOT_SOURCES[$i]}"
  destination="$TEST_ROOT${HOTSPOT_DESTINATIONS[$i]}"

  mkdir -p -- "$(dirname "$destination")"

  if [[ -e "$destination" || -L "$destination" ]]; then
    echo "ERROR: Destination already exists."
    rollback
    exit 1
  fi

  install -m 600 "$source_file" "$destination"
  created_files+=("$destination")

  echo "INSTALLED: ${HOTSPOT_DESTINATIONS[$i]}"
done

echo
echo "===== VERIFY RECOVERY ====="

for destination in "${HOTSPOT_DESTINATIONS[@]}"; do
  if [[ -e "$TEST_ROOT$destination" || -L "$TEST_ROOT$destination" ]]; then
    echo "FAIL: File remains after rollback: $destination"
    exit 1
  fi
done

echo "PASS: No installation files remain."
echo "PASS: Partial installation recovered successfully."
echo "No live system configuration was modified."
