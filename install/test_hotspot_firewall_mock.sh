#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIEW="$SCRIPT_DIR/hotspot-preview"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/bin"
LOG="$TEST_DIR/firewall.log"
: > "$LOG"

# Mock iptables and ip6tables.
# These record commands but never access the kernel firewall.
cat > "$TEST_DIR/bin/iptables" <<'MOCK'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$MOCK_FIREWALL_LOG"

case "${1:-}" in
    -L)
        exit 0
        ;;
    -N)
        exit 0
        ;;
    -C)
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
MOCK

cp "$TEST_DIR/bin/iptables" "$TEST_DIR/bin/ip6tables"
chmod 700 "$TEST_DIR/bin/iptables" "$TEST_DIR/bin/ip6tables"

export MOCK_FIREWALL_LOG="$LOG"
export PATH="$TEST_DIR/bin:$PATH"

echo "===== RUN GENERATED FIREWALL WITH MOCK COMMANDS ====="

bash "$PREVIEW/nomad-wifi-isolation.sh"

echo
echo "===== VERIFY EXPECTED RULES ====="

python3 - "$LOG" <<'PY'
from pathlib import Path
import sys

log = Path(sys.argv[1]).read_text()

checks = {
    "IPv4 INPUT hook":
        "iptables -I INPUT 1 -i wlan0 -j NOMAD-WIFI-INPUT" in log,

    "Docker forwarding hook":
        "iptables -I DOCKER-USER 1 -i wlan0 -j NOMAD-WIFI-FORWARD" in log,

    "DHCP allowed":
        "--dport 67 -j ACCEPT" in log,

    "DNS allowed":
        "--dport 53 -j ACCEPT" in log,

    "Captive portal allowed":
        "--dport 80 -j ACCEPT" in log,

    "Docker DNAT restriction":
        "--ctstate DNAT --ctorigdst 192.168.50.1" in log,

    "IPv4 INPUT blocked by default":
        "iptables -A NOMAD-WIFI-INPUT -j DROP" in log,

    "IPv4 FORWARD blocked by default":
        "iptables -A NOMAD-WIFI-FORWARD -j DROP" in log,

    "IPv6 INPUT hook":
        "ip6tables -I INPUT 1 -i wlan0 -j NOMAD-WIFI-INPUT" in log,

    "IPv6 FORWARD hook":
        "ip6tables -I FORWARD 1 -i wlan0 -j NOMAD-WIFI-FORWARD" in log,
}

for label, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {label}")

if not all(checks.values()):
    sys.exit(1)

print("\nPASS: All mock firewall checks completed.")
PY

echo
echo "===== TEST FIREWALL CLEANUP ====="

bash "$PREVIEW/nomad-wifi-isolation-remove.sh"

echo "PASS: Cleanup script completed with mocked commands."
echo "No live firewall rules were modified."
