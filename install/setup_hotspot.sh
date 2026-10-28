#!/usr/bin/env bash
set -Eeuo pipefail

# Project NOMAD Raspberry Pi 5 Edition
# Optional offline Wi-Fi hotspot setup
#
# This script is under development.
# Configuration changes are intentionally disabled.

HOTSPOT_INTERFACE="${HOTSPOT_INTERFACE:-wlan0}"
HOTSPOT_ADDRESS="${HOTSPOT_ADDRESS:-192.168.50.1}"
HOTSPOT_SSID="${HOTSPOT_SSID:-Project-NOMAD}"
NOMAD_PORT="${NOMAD_PORT:-8080}"

DRY_RUN=false
PREPARE=false

usage() {
  cat <<HELP
Project NOMAD Offline Wi-Fi Hotspot Setup

Usage:
  bash setup_hotspot.sh --dry-run
  bash setup_hotspot.sh --prepare
  bash setup_hotspot.sh --check-install
  bash setup_hotspot.sh --help

Options:
  --dry-run    Inspect system prerequisites without modifying anything
  --prepare    Generate configuration previews without installing them
  --check-install  Check for existing configuration conflicts
  --help       Display this help

Default configuration:
  Interface: ${HOTSPOT_INTERFACE}
  Address:   ${HOTSPOT_ADDRESS}
  SSID:      ${HOTSPOT_SSID}
  Portal:    http://${HOTSPOT_ADDRESS}:${NOMAD_PORT}

This version performs inspection only.
HELP
}

check_prerequisites() {
  echo "===== SYSTEM ====="
  if [[ -r /proc/device-tree/model ]]; then
    tr -d '\0' < /proc/device-tree/model
    echo
  fi

  echo
  echo "===== WIFI INTERFACE ====="
  if ! ip link show dev "$HOTSPOT_INTERFACE"; then
    echo "ERROR: Wireless interface $HOTSPOT_INTERFACE not found."
    exit 1
  fi

  echo
  echo "===== WIFI ACCESS POINT SUPPORT ====="
  if ! command -v iw >/dev/null 2>&1; then
    echo "WARNING: iw is not installed."
  elif iw list | awk '
    /Supported interface modes:/ { modes=1; next }
    modes && /^\tBand / { modes=0 }
    modes && /\* AP$/ { found=1 }
    END { exit !found }
  '; then
    echo "Wi-Fi adapter supports AP mode."
  else
    echo "WARNING: AP mode support could not be confirmed."
  fi

  echo
  echo "===== REQUIRED UTILITIES ====="
  for command_name in ip iw hostapd dnsmasq nginx iptables; do
    if command -v "$command_name" >/dev/null 2>&1; then
      echo "FOUND: $command_name"
    else
      echo "MISSING: $command_name"
    fi
  done

  echo
  echo "===== EXISTING CONFIGURATION ====="
  for file in \
    /etc/hostapd/hostapd.conf \
    /etc/dnsmasq.d/nomad-hotspot.conf \
    /etc/systemd/network/20-nomad-wlan0.network \
    /etc/nginx/sites-available/project-nomad \
    /etc/systemd/system/nomad-wifi-isolation.service
  do
    if [[ -e "$file" ]]; then
      echo "EXISTS: $file"
    else
      echo "AVAILABLE: $file"
    fi
  done

  echo
  echo "Inspection complete. No system changes were made."
}

case "${1:-}" in
  --dry-run)
    DRY_RUN=true
    ;;
  --prepare)
    PREPARE=true
    ;;
  --check-install)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    exec bash "${SCRIPT_DIR}/check_hotspot_install.sh"
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    usage
    echo
    echo "ERROR: Unsupported option. Use --help to see available commands."
    exit 1
    ;;
esac

if [[ "$DRY_RUN" == true ]]; then
  check_prerequisites
elif [[ "$PREPARE" == true ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  bash "${SCRIPT_DIR}/generate_hotspot_preview.sh"
fi
