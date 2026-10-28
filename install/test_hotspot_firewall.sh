#!/usr/bin/env bash
set -Eeuo pipefail

# Project NOMAD Raspberry Pi 5
# Static firewall preview validation.
#
# No sudo, iptables changes, or service restarts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIEW_DIR="$SCRIPT_DIR/hotspot-preview"

FIREWALL="$PREVIEW_DIR/nomad-wifi-isolation.sh"
REMOVAL="$PREVIEW_DIR/nomad-wifi-isolation-remove.sh"
SERVICE="$PREVIEW_DIR/nomad-wifi-isolation.service"

echo "===== FILE VALIDATION ====="

for file in "$FIREWALL" "$REMOVAL" "$SERVICE"; do
    [[ -f "$file" ]] || {
        echo "FAIL: Missing $file"
        exit 1
    }
    echo "PASS: $(basename "$file") exists"
done

echo
echo "===== BASH SYNTAX ====="

bash -n "$FIREWALL"
bash -n "$REMOVAL"

echo "PASS: Firewall and removal script syntax"

echo
echo "===== STATIC SECURITY CHECKS ====="

python3 - "$FIREWALL" "$REMOVAL" "$SERVICE" <<'PY'
from pathlib import Path
import sys

firewall = Path(sys.argv[1]).read_text()
removal = Path(sys.argv[2]).read_text()
service = Path(sys.argv[3]).read_text()

checks = {
    "Host INPUT chain":
        'INPUT_CHAIN="NOMAD-WIFI-INPUT"' in firewall,

    "Forwarding chain":
        'FORWARD_CHAIN="NOMAD-WIFI-FORWARD"' in firewall,

    "Docker forwarding hook":
        'iptables -I DOCKER-USER 1' in firewall,

    "DHCP allowed":
        "--dport 67 -j ACCEPT" in firewall,

    "DNS allowed":
        firewall.count("--dport 53 -j ACCEPT") >= 2,

    "Captive portal allowed":
        "--dport 80 -j ACCEPT" in firewall,

    "Original hotspot destination":
        '--ctorigdst "$HOTSPOT_IP"' in firewall,

    "DNAT connection matching":
        "--ctstate DNAT" in firewall,

    "IPv4 INPUT default blocking":
        'iptables -A "$INPUT_CHAIN" -j DROP' in firewall,

    "IPv4 FORWARD default blocking":
        'iptables -A "$FORWARD_CHAIN" -j DROP' in firewall,

    "IPv6 INPUT default blocking":
        'ip6tables -A "$INPUT_CHAIN" -j DROP' in firewall,

    "IPv6 FORWARD default blocking":
        'ip6tables -A "$FORWARD_CHAIN" -j DROP' in firewall,

    "Host INPUT cleanup":
        "remove_hook iptables INPUT" in removal,

    "Docker forwarding cleanup":
        "remove_hook iptables DOCKER-USER" in removal,

    "IPv6 cleanup":
        "remove_hook ip6tables FORWARD" in removal,

    "Systemd startup":
        "ExecStart=" in service,

    "Systemd cleanup":
        "ExecStop=" in service,

    "No invalid DNAT status matcher":
        "--ctstatus DNAT" not in firewall,

    "No obsolete NEW,DNAT matching":
        "--ctstate NEW,DNAT" not in firewall,
}

failed = False

for description, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {description}")
    if not passed:
        failed = True

if failed:
    sys.exit(1)

print("\nPASS: All static firewall checks completed.")
PY

echo
echo "No firewall rules or system services were modified."
