#!/bin/bash

set -e

if [ "$1" = "--help" ]; then
	echo "Usage:"
    echo "Without arguments, will create a new server configuration if there isn't one."
	echo "$(basename "$0") add/remove <peer name>"
	exit 1
fi

# Require root to change wg related settings
if ! [ "$(id -u)" = "0" ]; then
    echo "ERROR: root is required to configure WireGuard clients"
    exit 1
fi

if ! which wg &> /dev/null; then
    echo "ERROR: wg command does not exist, please install wireguard-tools"
    exit 1
fi

wg_iface="wg0"

if [ ! -f /etc/wireguard/$wg_iface.conf ]; then
chmod 700 /etc/wireguard/
mkdir -p /etc/wireguard/server/
mkdir /etc/wireguard/clients/
curl https://api.ipify.org > /etc/wireguard/server/ipextern
wg genkey | tee /etc/wireguard/server/server.key
server_privkey=$(< "/etc/wireguard/server/server.key")

cat >> /etc/wireguard/$wg_iface.conf <<-EOM
[Interface]
# Wireguard interface will be run at 10.1.0.0
Address = 10.1.0.0/24

# Wireguard Server private key - server.key
PrivateKey = $server_privkey

# Clients will connect to UDP port 51820
ListenPort = 51820

EOM

if which systemctl &> /dev/null; then
    systemctl enable --now wg-quick@$wg_iface
fi

if which firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=51820/udp --zone=public
    firewall-cmd --reload
fi
else

# if $1 empty
if [ -z "$1" ]; then
    echo "/etc/wireguard/$wg_iface.conf already exists."
    exit 1
fi
# Add peer
if [ "$1" = "add" ]; then
name="$2"
# if name empty then exit
if [ -z "$name" ]; then
    echo "ERROR: User name is mandatory."
    exit 1
fi

# if user name exists then exit
if grep -q "# $name" "/etc/wireguard/$wg_iface.conf"; then
    echo "ERROR: User $name already exists"
    exit 1
fi

curl https://api.ipify.org > /etc/wireguard/server/ipextern

# Params
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
fi

if [ "$1" = "remove" ]; then

name="$2"

# if name empty then exit
if [ -z "$name" ]; then
    echo "ERROR: User name is mandatory."
    exit 1
fi

# Remove peer from config if it exists
if grep -q "$name" "/etc/wireguard/$wg_iface.conf"; then
    rm /etc/wireguard/clients/$name.conf
    sed -i "/^# $name/,/^$/d" /etc/wireguard/$wg_iface.conf
    wg syncconf $wg_iface <(wg-quick strip $wg_iface)
else
    echo "ERROR: User $name does not exist."
fi
fi
fi
