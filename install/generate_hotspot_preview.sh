#!/usr/bin/env bash
set -Eeuo pipefail

# Project NOMAD Raspberry Pi 5 Edition
# Offline hotspot configuration preview only.
# Does not install or modify system configuration.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/hotspot-preview"

HOTSPOT_IP="192.168.50.1"
HOTSPOT_INTERFACE="wlan0"
HOTSPOT_SSID="Project-NOMAD"
NOMAD_PORT="8080"

mkdir -p "$OUTPUT_DIR"

cat > "$OUTPUT_DIR/20-nomad-wlan0.network" <<CONFIG
[Match]
Name=${HOTSPOT_INTERFACE}

[Network]
Address=${HOTSPOT_IP}/24
DHCP=no
LinkLocalAddressing=no
IPv6AcceptRA=no
ConfigureWithoutCarrier=yes
CONFIG

cat > "$OUTPUT_DIR/hostapd.conf" <<CONFIG
interface=${HOTSPOT_INTERFACE}
driver=nl80211
ssid=${HOTSPOT_SSID}
country_code=US
hw_mode=g
channel=6
wpa=2
wpa_passphrase=REPLACE_WITH_SECURE_PASSWORD
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
CONFIG

cat > "$OUTPUT_DIR/nomad-hotspot.conf" <<CONFIG
interface=${HOTSPOT_INTERFACE}
bind-dynamic

dhcp-range=192.168.50.50,192.168.50.200,255.255.255.0,12h
dhcp-option=3,${HOTSPOT_IP}
dhcp-option=6,${HOTSPOT_IP}

no-resolv
address=/nomad.local/${HOTSPOT_IP}

address=/www.msftconnecttest.com/${HOTSPOT_IP}
address=/www.msftncsi.com/${HOTSPOT_IP}
address=/connectivitycheck.gstatic.com/${HOTSPOT_IP}
address=/clients3.google.com/${HOTSPOT_IP}
address=/captive.apple.com/${HOTSPOT_IP}
address=/www.apple.com/${HOTSPOT_IP}
address=/detectportal.firefox.com/${HOTSPOT_IP}
address=/network-test.debian.org/${HOTSPOT_IP}
CONFIG

cat > "$OUTPUT_DIR/project-nomad.nginx" <<CONFIG
# Project NOMAD Raspberry Pi 5
# Offline hotspot captive portal

server {
    listen ${HOTSPOT_IP}:80;
    server_name
        www.msftconnecttest.com
        www.msftncsi.com
        connectivitycheck.gstatic.com
        clients3.google.com
        captive.apple.com
        www.apple.com
        detectportal.firefox.com
        network-test.debian.org;

    return 302 http://${HOTSPOT_IP}/;
}

server {
    listen ${HOTSPOT_IP}:80 default_server;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:${NOMAD_PORT};
        proxy_http_version 1.1;

        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_buffering off;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
CONFIG

cat > "$OUTPUT_DIR/nomad-wifi-isolation.sh" <<'CONFIG'
#!/usr/bin/env bash
set -Eeuo pipefail

# DEVELOPMENT PREVIEW ONLY.
# DO NOT EXECUTE ON A WORKING NOMAD SERVER.

WIFI_INTERFACE="wlan0"
HOTSPOT_IP="192.168.50.1"

INPUT_CHAIN="NOMAD-WIFI-INPUT"
FORWARD_CHAIN="NOMAD-WIFI-FORWARD"

ALLOWED_PORTS=(8080 8090 8100 8200 8300 8400)

# Refuse existing NOMAD-named chains before making any changes.
# Existing chains have not been verified as installer-owned.
for firewall in iptables ip6tables; do
    for chain in "$INPUT_CHAIN" "$FORWARD_CHAIN"; do
        if "$firewall" -L "$chain" -n >/dev/null 2>&1; then
            echo "ERROR: Existing firewall chain: $firewall $chain" >&2
            echo "Refusing to modify an unverified chain." >&2
            exit 2
        fi
    done
done

# Docker must already be running.
iptables -L DOCKER-USER -n >/dev/null

# IPv4 host INPUT protection.
iptables -N "$INPUT_CHAIN" 2>/dev/null || true
iptables -F "$INPUT_CHAIN"

iptables -A "$INPUT_CHAIN" \
    -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

iptables -A "$INPUT_CHAIN" \
    -p udp --dport 67 -j ACCEPT

iptables -A "$INPUT_CHAIN" \
    -p udp --dport 53 -j ACCEPT

iptables -A "$INPUT_CHAIN" \
    -p tcp --dport 53 -j ACCEPT

iptables -A "$INPUT_CHAIN" \
    -p tcp -d "$HOTSPOT_IP" --dport 80 -j ACCEPT

iptables -A "$INPUT_CHAIN" -j DROP

iptables -C INPUT -i "$WIFI_INTERFACE" \
    -j "$INPUT_CHAIN" 2>/dev/null ||
    iptables -I INPUT 1 -i "$WIFI_INTERFACE" \
        -j "$INPUT_CHAIN"

# IPv4 Docker forwarding protection.
iptables -N "$FORWARD_CHAIN" 2>/dev/null || true
iptables -F "$FORWARD_CHAIN"

for port in "${ALLOWED_PORTS[@]}"; do
    for bridge in docker0 br+; do
        iptables -A "$FORWARD_CHAIN" \
            -p tcp \
            -m conntrack --ctstate DNAT \
            --ctorigdst "$HOTSPOT_IP" \
            --ctorigdstport "$port" \
            -o "$bridge" \
            -j RETURN
    done
done

iptables -A "$FORWARD_CHAIN" -j DROP

iptables -C DOCKER-USER -i "$WIFI_INTERFACE" \
    -j "$FORWARD_CHAIN" 2>/dev/null ||
    iptables -I DOCKER-USER 1 -i "$WIFI_INTERFACE" \
        -j "$FORWARD_CHAIN"

# IPv6: block traffic arriving through the hotspot.
# This preview intentionally provides no IPv6 service access.
ip6tables -N "$INPUT_CHAIN" 2>/dev/null || true
ip6tables -F "$INPUT_CHAIN"
ip6tables -A "$INPUT_CHAIN" -j DROP

ip6tables -C INPUT -i "$WIFI_INTERFACE" \
    -j "$INPUT_CHAIN" 2>/dev/null ||
    ip6tables -I INPUT 1 -i "$WIFI_INTERFACE" \
        -j "$INPUT_CHAIN"

ip6tables -N "$FORWARD_CHAIN" 2>/dev/null || true
ip6tables -F "$FORWARD_CHAIN"
ip6tables -A "$FORWARD_CHAIN" -j DROP

ip6tables -C FORWARD -i "$WIFI_INTERFACE" \
    -j "$FORWARD_CHAIN" 2>/dev/null ||
    ip6tables -I FORWARD 1 -i "$WIFI_INTERFACE" \
        -j "$FORWARD_CHAIN"
CONFIG

cat > "$OUTPUT_DIR/nomad-wifi-isolation-remove.sh" <<'CONFIG'
#!/usr/bin/env bash
set -Eeuo pipefail

# DEVELOPMENT PREVIEW ONLY.
# Remove only the Project NOMAD firewall hooks and chains.

INPUT_CHAIN="NOMAD-WIFI-INPUT"
FORWARD_CHAIN="NOMAD-WIFI-FORWARD"

remove_hook() {
    local firewall="$1"
    local parent="$2"
    local interface="$3"
    local chain="$4"

    while "$firewall" -C "$parent" -i "$interface" \
        -j "$chain" 2>/dev/null; do
        "$firewall" -D "$parent" -i "$interface" -j "$chain"
    done
}

remove_chain() {
    local firewall="$1"
    local chain="$2"

    if "$firewall" -L "$chain" -n >/dev/null 2>&1; then
        "$firewall" -F "$chain"
        "$firewall" -X "$chain"
    fi
}

remove_hook iptables INPUT wlan0 "$INPUT_CHAIN"
remove_hook iptables DOCKER-USER wlan0 "$FORWARD_CHAIN"

remove_chain iptables "$INPUT_CHAIN"
remove_chain iptables "$FORWARD_CHAIN"

remove_hook ip6tables INPUT wlan0 "$INPUT_CHAIN"
remove_hook ip6tables FORWARD wlan0 "$FORWARD_CHAIN"

remove_chain ip6tables "$INPUT_CHAIN"
remove_chain ip6tables "$FORWARD_CHAIN"
CONFIG

cat > "$OUTPUT_DIR/nomad-wifi-isolation.service" <<'CONFIG'
[Unit]
Description=Project NOMAD Offline Wi-Fi Isolation
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/nomad-wifi-isolation.sh
ExecStop=/usr/local/sbin/nomad-wifi-isolation-remove.sh

[Install]
WantedBy=multi-user.target
CONFIG

chmod 700 "$OUTPUT_DIR/nomad-wifi-isolation.sh"
chmod 700 "$OUTPUT_DIR/nomad-wifi-isolation-remove.sh"
chmod 600 "$OUTPUT_DIR/hostapd.conf"

echo
echo "Hotspot configuration preview generated:"
echo "$OUTPUT_DIR"
echo
echo "No system configuration was modified."
