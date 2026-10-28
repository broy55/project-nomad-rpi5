#!/usr/bin/env bash

# Project NOMAD Raspberry Pi 5
# Shared hotspot installation file manifest.
#
# This file defines configuration sources and destinations.
# Sourcing it does not modify the system.

HOTSPOT_SOURCES=(
    "20-nomad-wlan0.network"
    "hostapd.conf"
    "nomad-hotspot.conf"
    "project-nomad.nginx"
    "nomad-wifi-isolation.sh"
    "nomad-wifi-isolation-remove.sh"
    "nomad-wifi-isolation.service"
)

HOTSPOT_DESTINATIONS=(
    "/etc/systemd/network/20-nomad-wlan0.network"
    "/etc/hostapd/hostapd.conf"
    "/etc/dnsmasq.d/nomad-hotspot.conf"
    "/etc/nginx/sites-available/project-nomad"
    "/usr/local/sbin/nomad-wifi-isolation.sh"
    "/usr/local/sbin/nomad-wifi-isolation-remove.sh"
    "/etc/systemd/system/nomad-wifi-isolation.service"
)

HOTSPOT_MODES=(
    "644"
    "600"
    "644"
    "644"
    "700"
    "700"
    "644"
)

if (( ${#HOTSPOT_SOURCES[@]} != ${#HOTSPOT_DESTINATIONS[@]} ||
      ${#HOTSPOT_SOURCES[@]} != ${#HOTSPOT_MODES[@]} )); then
    echo "ERROR: Hotspot manifest arrays have different lengths." >&2
    return 1 2>/dev/null || exit 1
fi
