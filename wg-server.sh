#!/bin/bash

# Copyright (c) 2025 Mihaly Csaba
# 
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT

set -euo pipefail

# --- Customizable variables ---
wg_address="10.1.0.0"
wg_listen_port="51820"
wg_iface="wg0"
server_ip=""
# -----------------------------

# Display usage information
display_usage() {
        cat <<EOF
Usage:
    $0 [-a peer] [-r peer] [-l] [-h]
Options:
    If no options, initialize server
    -a <peer>   Add a WireGuard peer with name <peer>
    -d <peer>   Delete a WireGuard peer with name <peer>
    -r          Reload WireGuard configuration, stop the interface if no config file found
    -l          List all WireGuard peers
    -h          Show this help message
EOF
}

# Print error message and exit
err() { echo "ERROR: $*" >&2; exit 1; }

# Ensure the script is run as root
require_root() {
    [ "$(id -u)" = "0" ] || err "root is required to configure WireGuard"
}

# Ensure a required command is available
require_cmd() {
    command -v "$1" &>/dev/null || err "'$1' command not found, please install it."
}

# Get the server's public IP address
get_public_ip() {
    # Only get public IP if server_ip is empty
    if [ -z "$server_ip" ]; then
        if ! curl -fsSL https://api.ipify.org >"$server_dir/ipextern"; then
            if [ ! -f "$server_dir/ipextern" ]; then
                err "Failed to get public IP"
            fi
        fi
        server_ip=$(<"$server_dir/ipextern")
    fi
}

# ---- MAIN ----

config_file="/etc/wireguard/${wg_iface}.conf"
server_dir="/etc/wireguard/server"
clients_dir="/etc/wireguard/clients"
ipv4_mask="32"

# Show help if requested
if [[ "${1:-}" == "--help" ]]; then
    display_usage
    exit 0
fi

require_root
require_cmd wg

reload_wg_config() {
    if [ -f "$config_file" ]; then
        wg syncconf "$wg_iface" <(wg-quick strip "$wg_iface")
        echo "WireGuard config reloaded."
    else
        echo "No config file found to reload."
    fi
}

add_peer() {
    local name="$1"
    [[ -n "$name" ]] || err "User name is mandatory."
    # Only allow letters, numbers, underscores, and dashes
    if ! echo "$name" | grep -Eq '^[A-Za-z0-9_-]+$'; then
        err "Peer name may only contain letters, numbers, dash, and underscore."
    fi
    grep -q "^# $name\$" "$config_file" && err "User $name already exists"

    # Get the server's public IP address
    get_public_ip

    local ipv4_prefix
    ipv4_prefix="${wg_address%.*}."

    # Get server keys
    server_privkey=$(<"$server_dir/server.key")
    server_pubkey=$(<"$server_dir/server.pub")

    # Generate client keys
    client_privkey=$(wg genkey)
    client_pubkey=$(echo -n "$client_privkey" | wg pubkey)

    # Find an available IPv4 address for the new peer
    for client_number in $(seq 1 255); do
        client_ipv4="${ipv4_prefix}${client_number}/${ipv4_mask}"
        grep -q "$client_ipv4" "$config_file" && continue

        # Add peer to server config
        {
            echo
            echo "# $name"
            echo "[Peer]"
            echo "PublicKey = $client_pubkey"
            echo "AllowedIPs = $client_ipv4"
        } >>"$config_file"

        # Generate client config file
        {
            echo "[Interface]"
            echo "PrivateKey = $client_privkey"
            echo "Address = $client_ipv4"
            echo
            echo "[Peer]"
            echo "PublicKey = $server_pubkey"
            echo "AllowedIPs = ${wg_address}/$ipv4_mask"
            echo "Endpoint = $server_ip:$wg_listen_port"
        } >"$clients_dir/$name.conf"

    # Apply the new configuration
    reload_wg_config

        # Output the client config
        echo "########## START OF CONFIG ##########"
        echo
        cat "$clients_dir/$name.conf"
        echo
        echo "########### END OF CONFIG ###########"
        exit 0
    done

    err "No available peerIP address"
}

delete_peer() {
    local name="$1"
    [[ -n "$name" ]] || err "User name is mandatory."
    if grep -q "^# $name\$" "$config_file"; then
        rm -f "$clients_dir/$name.conf"
        # Remove peer block (from comment line to next blank line or EOF)
        sed -i "/^# $name\$/,/^$/d" "$config_file"
        reload_wg_config
        echo "User $name removed."
        exit 0
    else
        err "User $name does not exist."
    fi
}

list_peers() {
    if [ ! -f "$config_file" ]; then
        echo "No config file found: $config_file"
        exit 1
    fi
    echo "Configured peers:"
    # List lines starting with '# ' (peer name comments)
    grep '^# ' "$config_file" | sed 's/^# //'
}

while getopts ":a:d:lhr" opt; do
    case $opt in
        a)
            add_peer "$OPTARG"
            ;;
        d)
            delete_peer "$OPTARG"
            ;;
        l)
            list_peers
            exit 0
            ;;
        h)
            display_usage
            exit 0
            ;;
        r)
            reload_wg_config
            exit 0
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            display_usage
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            display_usage
            exit 1
            ;;
    esac
done

# If no options, initialize server
if [ $OPTIND -eq 1 ]; then
    if [ ! -f "$config_file" ]; then
        # Create necessary directories with secure permissions
        mkdir -p "$server_dir" "$clients_dir"
        chmod -R 600 /etc/wireguard

        # Get the server's public IP address
        get_public_ip

        # Generate server private key
        wg genkey > "$server_dir/server.key"
        server_privkey=$(<"$server_dir/server.key")
        echo -n "$server_privkey" | wg pubkey > "$server_dir/server.pub"
        # Write the server WireGuard config file
        {
            echo "[Interface]"
            echo "Address = $wg_address/$ipv4_mask"
            echo "PrivateKey = $server_privkey"
            echo "ListenPort = $wg_listen_port"
            echo
        } >"$config_file"

        # Enable and start the WireGuard service if systemd is available
        if command -v systemctl &>/dev/null; then
            systemctl enable --now "wg-quick@$wg_iface"
        fi

        # Open the WireGuard port in the firewall (firewalld or ufw)
        if command -v firewall-cmd &>/dev/null; then
            firewall-cmd --permanent --add-port=${wg_listen_port}/udp --zone=public
            firewall-cmd --reload
        elif command -v ufw &>/dev/null; then
            ufw allow ${wg_listen_port}/udp
        else
            echo "Warning: Neither firewalld nor ufw found. Please ensure UDP port ${wg_listen_port} is open." >&2
        fi

        reload_wg_config
        echo "WireGuard server initialized from $config_file"
        exit 0
    else
        echo "$config_file already exists."
        exit 0
    fi
fi
