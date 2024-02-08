#!/bin/bash

set -e

# Require root to change wg-related settings
if ! [ "$(id -u)" = "0" ]; then
    echo "ERROR: root is required to configure WireGuard clients"
    exit 1
fi

if ! which wg &> /dev/null; then
    echo "wg command does not exist, please install wireguard-tools"
    exit 1
fi

chmod 700 /etc/wireguard/
mkdir -p /etc/wireguard/server/
mkdir /etc/wireguard/clients/
curl https://api.ipify.org > /etc/wireguard/server/ipextern
wg genkey | tee /etc/wireguard/server/server.key
server_privkey=$(< "/etc/wireguard/server/server.key")

cat >> /etc/wireguard/wg0.conf <<-EOM
[Interface]
# Wireguard interface will be run at 10.1.0.0
Address = 10.1.0.0/24

# Wireguard Server private key - server.key
PrivateKey = $server_privkey

# Clients will connect to UDP port 51820
ListenPort = 51820

EOM

if which systemctl &> /dev/null; then
    systemctl enable --now wg-quick@wg0
fi

if which firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=51820/udp --zone=public
    firewall-cmd --reload
fi
