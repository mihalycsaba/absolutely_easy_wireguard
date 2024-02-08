#!/bin/bash

set -e
wg_iface="wg0"

# if name empty then exit
if [ -z "$1" ]; then
    echo "ERROR: User name is mandatory."
    exit 1
fi

# Require root to change wg-related settings
if ! [ "$(id -u)" = "0" ]; then
    echo "ERROR: root is required to configure WireGuard clients"
    exit 1
fi

# if user name exists then exit
if grep -q "# $1" "/etc/wireguard/$wg_iface.conf"; then
    echo "ERROR: User $1 already exists"
    exit 1
fi

curl https://api.ipify.org > /etc/wireguard/server/ipextern

# Params
name="$1"
# Modify these per-server
config_file="/etc/wireguard/$wg_iface.conf"
server_ip=$(< "/etc/wireguard/server/ipextern")
server_port="51820"
ipv4_prefix="10.1.0."
ipv4_mask="32"

# Generate and store keypair
server_privkey=$(< "/etc/wireguard/server/server.key")   ## put server private key here and based on that public key is generated
server_pubkey=$(echo -n "$server_privkey" | wg pubkey)
client_privkey=$(wg genkey)
client_pubkey=$(echo -n "$client_privkey" | wg pubkey)

# Create IPv4/6 addresses based on client ID
client_number=1
while [ $client_number -lt 256 ]; do
    client_ipv4="$ipv4_prefix$client_number/$ipv4_mask"
    if grep -q "$client_ipv4" "$config_file"; then
        # Can't add duplicate IPs
	    ((client_number++))
    else
# Add peer to config file (blank line is on purpose)
cat >> $config_file <<-EOM

# $name
[Peer]
PublicKey = $client_pubkey
AllowedIPs = $client_ipv4
EOM

server_number="0"
# Make client config
cat >> /etc/wireguard/clients/$name.conf <<-EOM
[Interface]
PrivateKey = $client_privkey
Address = $client_ipv4

[Peer]
PublicKey = $server_pubkey
AllowedIPs = $ipv4_prefix$server_number/$ipv4_mask
Endpoint = $server_ip:$server_port
EOM

wg syncconf $wg_iface <(wg-quick strip $wg_iface)

# Output client configuration
echo "########## START CONFIG ##########
"
cat /etc/wireguard/clients/$name.conf
echo "
########### END CONFIG ###########"
        break
    fi
done

if [ "$client_number" -gt 255 ]; then
    echo "ERROR: No available IPv4 address"
fi
