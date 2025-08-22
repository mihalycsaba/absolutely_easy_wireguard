#!/bin/bash

set -e

# Display usage instructions if --help flag is used
if [ "$1" = "--help" ]; then
    echo "Usage:"
    echo "Without arguments, will create a new server configuration if there isn't one."
    echo "$(basename "$0") add/remove <peer name>"
    exit 1
fi

# Require root privileges to make WireGuard configuration changes
if ! [ "$(id -u)" = "0" ]; then
    echo "ERROR: root is required to configure WireGuard"
    exit 1
fi

# Check if wireguard-tools is installed
if ! which wg &>/dev/null; then
    echo "ERROR: wg command does not exist, please install wireguard-tools"
    exit 1
fi

wg_iface="wg0"

# --- Server Initialization ---
if [ ! -f /etc/wireguard/$wg_iface.conf ]; then
    # Secure the /etc/wireguard directory and create necessary subdirectories
    chmod 700 /etc/wireguard/
    mkdir -p /etc/wireguard/server/
    mkdir /etc/wireguard/clients/

    # Save the server's public IP to a file for use in client configs
    curl https://api.ipify.org >/etc/wireguard/server/ipextern

    # Generate and store the server's private key
    wg genkey | tee /etc/wireguard/server/server.key
    server_privkey=$(<"/etc/wireguard/server/server.key")

    # Write the initial WireGuard server configuration
cat >>/etc/wireguard/$wg_iface.conf <<-EOM
[Interface]
# Wireguard interface will be run at 10.1.0.0
Address = 10.1.0.0/24

# Wireguard Server private key - server.key
PrivateKey = $server_privkey

# Clients will connect to UDP port 51820
ListenPort = 51820

EOM

    # Enable and start the WireGuard service if systemctl is present
    if which systemctl &>/dev/null; then
        systemctl enable --now wg-quick@$wg_iface
    fi

    # Open UDP port 51820 in the firewall if firewalld is present
    if which firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port=51820/udp --zone=public
        firewall-cmd --reload
    fi

else

    # --- Peer Management (add/remove) ---

    # If no argument is given, only notify that config exists
    if [ -z "$1" ]; then
        echo "/etc/wireguard/$wg_iface.conf already exists."
        exit 1
    fi

    # --- Add Peer ---
    if [ "$1" = "add" ]; then
        name="$2"
        # Ensure a peer name is specified
        if [ -z "$name" ]; then
            echo "ERROR: User name is mandatory."
            exit 1
        fi

        # Prevent duplicate peer names
        if grep -q "# $name" "/etc/wireguard/$wg_iface.conf"; then
            echo "ERROR: User $name already exists"
            exit 1
        fi

        # Refresh the server's public IP in case it changed
        curl https://api.ipify.org >/etc/wireguard/server/ipextern

        # --- Server & Client Parameters ---
        config_file="/etc/wireguard/$wg_iface.conf"
        server_ip=$(<"/etc/wireguard/server/ipextern")
        server_port="51820"
        ipv4_prefix="10.1.0."
        ipv4_mask="32"

        # Generate server public key from stored private key
        server_privkey=$(<"/etc/wireguard/server/server.key")
        server_pubkey=$(echo -n "$server_privkey" | wg pubkey)

        # Generate client keypair
        client_privkey=$(wg genkey)
        client_pubkey=$(echo -n "$client_privkey" | wg pubkey)

        # Find the first available IPv4 address for the client
        client_number=1
        while [ $client_number -lt 256 ]; do
            client_ipv4="$ipv4_prefix$client_number/$ipv4_mask"
            if grep -q "$client_ipv4" "$config_file"; then
                # IP already in use; try the next one
                ((client_number++))
            else
                # Add new peer to the server config
                cat >>$config_file <<-EOM

# $name
[Peer]
PublicKey = $client_pubkey
AllowedIPs = $client_ipv4
EOM

                server_number="0"
                # Generate client configuration file
                cat >>/etc/wireguard/clients/$name.conf <<-EOM
[Interface]
PrivateKey = $client_privkey
Address = $client_ipv4

[Peer]
PublicKey = $server_pubkey
AllowedIPs = $ipv4_prefix$server_number/$ipv4_mask
Endpoint = $server_ip:$server_port
EOM

                # Reload WireGuard configuration without restarting the interface
                wg syncconf $wg_iface <(wg-quick strip $wg_iface)

                # Output the client configuration for user to copy
                echo "########## START CONFIG ##########
"
                cat /etc/wireguard/clients/$name.conf
                echo "
########### END CONFIG ###########"
                break
            fi
        done

        # If all IPs are taken, report an error
        if [ "$client_number" -gt 255 ]; then
            echo "ERROR: No available IPv4 address"
        fi
    fi

    # --- Remove Peer ---
    if [ "$1" = "remove" ]; then
        name="$2"
        # Ensure a peer name is specified
        if [ -z "$name" ]; then
            echo "ERROR: User name is mandatory."
            exit 1
        fi

        # Remove peer from server and delete client config if it exists
        if grep -q "$name" "/etc/wireguard/$wg_iface.conf"; then
            rm /etc/wireguard/clients/$name.conf
            # Remove the peer block from the server config
            sed -i "/^# $name/,/^$/d" /etc/wireguard/$wg_iface.conf
            # Reload WireGuard configuration
            wg syncconf $wg_iface <(wg-quick strip $wg_iface)
        else
            echo "ERROR: User $name does not exist."
        fi
    fi

    # --- Unknown Command Handler ---
    if [ "$1" != "add" ] && [ "$1" != "remove" ]; then
        echo "ERROR: Unknown command $1, please use 'add' or 'remove'."
    fi

fi
