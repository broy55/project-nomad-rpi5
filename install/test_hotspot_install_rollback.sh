#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIEW_DIR="$SCRIPT_DIR/hotspot-preview"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

# Load shared configuration manifest.
source "$SCRIPT_DIR/hotspot_manifest.sh"

# Create an unrelated existing configuration.
mkdir -p "$TEST_ROOT/etc/nginx/sites-available"
printf '%s\n' "EXISTING CONFIGURATION" \
  > "$TEST_ROOT/etc/nginx/sites-available/existing-site"

echo "===== SIMULATED INSTALLATION PREFLIGHT ====="
bash "$SCRIPT_DIR/plan_hotspot_install.sh" --root "$TEST_ROOT"

echo
echo "===== SIMULATED INSTALLATION ====="

for i in "${!HOTSPOT_SOURCES[@]}"; do
  source_file="$PREVIEW_DIR/${HOTSPOT_SOURCES[$i]}"
  destination="$TEST_ROOT${HOTSPOT_DESTINATIONS[$i]}"

  [[ -f "$source_file" && ! -e "$destination" && ! -L "$destination" ]] || {
    echo "ERROR: Missing source or conflicting destination."
    exit 1
  }

  mkdir -p -- "$(dirname "$destination")"
  cp --update=none-fail -- "$source_file" "$destination"

  [[ -f "$destination" ]] || exit 1
  echo "INSTALLED: ${HOTSPOT_DESTINATIONS[$i]}"
done

echo
echo "===== VERIFY INSTALLATION ====="

for i in "${!HOTSPOT_SOURCES[@]}"; do
  cmp -s \
    "$PREVIEW_DIR/${HOTSPOT_SOURCES[$i]}" \
    "$TEST_ROOT${HOTSPOT_DESTINATIONS[$i]}" || {
      echo "ERROR: Installed file differs from source."
      exit 1
    }
done

echo "PASS: All seven files match their sources."

echo
echo "===== SIMULATED ROLLBACK ====="

for destination in "${HOTSPOT_DESTINATIONS[@]}"; do
  rm -- "$TEST_ROOT$destination"
  echo "REMOVED: $destination"
done

echo
echo "===== VERIFY ROLLBACK ====="

for destination in "${HOTSPOT_DESTINATIONS[@]}"; do
  if [[ -e "$TEST_ROOT$destination" || -L "$TEST_ROOT$destination" ]]; then
    echo "FAIL: File remains after rollback: $destination"
    exit 1
  fi
done

echo "PASS: All seven files removed."

if [[ "$(cat "$TEST_ROOT/etc/nginx/sites-available/existing-site")" \
      == "EXISTING CONFIGURATION" ]]; then
    echo "PASS: Unrelated existing configuration preserved."
else
    echo "FAIL: Existing configuration was modified."
    exit 1
fi

echo "No live system files, services, or firewall rules were modified."
