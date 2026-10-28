#!/usr/bin/env bash
set -Eeuo pipefail

# Project NOMAD Raspberry Pi 5 Edition
# Read-only hotspot installation safety checks.

conflicts=0

echo "===== EXISTING HOTSPOT CONFIGURATION ====="

files=(
  /etc/hostapd/hostapd.conf
  /etc/dnsmasq.d/nomad-hotspot.conf
  /etc/systemd/network/20-nomad-wlan0.network
  /etc/nginx/sites-available/project-nomad
  /etc/systemd/system/nomad-wifi-isolation.service
  /usr/local/sbin/nomad-wifi-isolation.sh
)

for file in "${files[@]}"; do
  if [[ -e "$file" || -L "$file" ]]; then
    echo "CONFLICT: $file already exists"
    ((conflicts+=1))
  else
    echo "AVAILABLE: $file"
  fi
done

echo
echo "===== NETWORK MANAGEMENT ====="

for service in systemd-networkd NetworkManager; do
  if systemctl is-active --quiet "$service"; then
    echo "ACTIVE: $service"
  else
    echo "INACTIVE: $service"
  fi
done

echo
echo "===== EXISTING LISTENERS ====="

if command -v ss >/dev/null 2>&1; then
  ss -ltn '( sport = :80 )'
fi

echo
echo "===== RESULT ====="

if (( conflicts > 0 )); then
  echo "INSTALLATION BLOCKED: $conflicts existing configuration path(s)."
  echo "No files or services were changed."
  exit 2
fi

echo "No conflicts found among the checked configuration paths."
echo "Additional validation is required before installation."
