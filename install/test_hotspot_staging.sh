#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIEW_DIR="$SCRIPT_DIR/hotspot-preview"

# Generate configuration previews.
bash "$SCRIPT_DIR/generate_hotspot_preview.sh"

# Load password helper.
source "$SCRIPT_DIR/hotspot_password.sh"

# Request password interactively.
read_hotspot_password

# Create private staging directory.
STAGING_DIR="$(mktemp -d)"
trap 'unset HOTSPOT_PASSWORD; rm -rf "$STAGING_DIR"' EXIT

# Copy configuration previews.
cp -a "$PREVIEW_DIR/." "$STAGING_DIR/"

# Pass password through a private temporary file rather than
# command-line arguments or environment variables.
PASSWORD_FILE="$STAGING_DIR/.password"
printf '%s' "$HOTSPOT_PASSWORD" > "$PASSWORD_FILE"
unset HOTSPOT_PASSWORD

python3 - "$STAGING_DIR/hostapd.conf" "$PASSWORD_FILE" <<'PY'
from pathlib import Path
import sys

config_path = Path(sys.argv[1])
password_path = Path(sys.argv[2])

password = password_path.read_text()
config = config_path.read_text()

placeholder = "REPLACE_WITH_SECURE_PASSWORD"

if config.count(placeholder) != 1:
    raise SystemExit("Expected password placeholder not found.")

config_path.write_text(config.replace(placeholder, password))
PY

rm -f "$PASSWORD_FILE"

echo
echo "===== STAGED CONFIGURATION ====="

if grep -q '^wpa_passphrase=' "$STAGING_DIR/hostapd.conf"; then
    echo "PASS: WPA2 password inserted."
else
    echo "FAIL: WPA2 password missing."
    exit 1
fi

if grep -q 'REPLACE_WITH_SECURE_PASSWORD' "$STAGING_DIR/hostapd.conf"; then
    echo "FAIL: Placeholder remains."
    exit 1
fi

echo
echo "===== FILE PERMISSIONS ====="
stat -c '%a %n' "$STAGING_DIR/hostapd.conf"

echo
echo "===== GENERATED FILE COUNT ====="
find "$STAGING_DIR" -maxdepth 1 -type f | wc -l

echo
echo "Staging test passed."
echo "Temporary files will be removed automatically."
echo "No system configuration was modified."
