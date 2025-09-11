#!/bin/bash

# Copyright (c) 2025 Mihaly Csaba
# 
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT

set -euo pipefail

# --- Customizable variables ---
server_address="10.1.0.0/24"
server_listen_port="51820"
# -----------------------------

# Display usage information
display_usage() {
    cat <<EOF
Usage:
  $(basename "$0")                # Initialize new server config if missing
  $(basename "$0") add <peer>     # Add a WireGuard peer with name <peer>
  $(basename "$0") remove <peer>  # Remove a WireGuard peer with name <peer>
  $(basename "$0") --help         # Show this help message
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
    if ! curl -fsSL https://api.ipify.org >"$server_dir/ipextern"; then
        if [ ! -f "$server_dir/ipextern" ]; then
            err "Failed to get public IP"
        fi
    fi
}

# ---- MAIN ----

wg_iface="wg0"
config_file="/etc/wireguard/${wg_iface}.conf"
server_dir="/etc/wireguard/server"
clients_dir="/etc/wireguard/clients"

# Show help if requested
if [[ "${1:-}" == "--help" ]]; then
    display_usage
    exit 0
fi

require_root
require_cmd wg

# --- Server Initialization ---
if [ ! -f "$config_file" ]; then
    # Create necessary directories with secure permissions
    mkdir -p "$server_dir" "$clients_dir"
    chmod -R 700 /etc/wireguard

    # Get the server's public IP address
    get_public_ip
    server_ip=$(<"$server_dir/ipextern")

    # Generate server private key
    wg genkey > "$server_dir/server.key"
    server_privkey=$(<"$server_dir/server.key")
    echo -n "$server_privkey" | wg pubkey > "$server_dir/server.pub"
    # Write the server WireGuard config file
    {
        echo "[Interface]"
        echo "Address = $server_address"
        echo "PrivateKey = $server_privkey"
        echo "ListenPort = $server_listen_port"
        echo
    } >"$config_file"

    # Enable and start the WireGuard service if systemd is available
    if command -v systemctl &>/dev/null; then
        systemctl enable --now "wg-quick@$wg_iface"
    fi

    # Open the WireGuard port in the firewall (firewalld or ufw)
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port=${server_listen_port}/udp --zone=public
        firewall-cmd --reload
    elif command -v ufw &>/dev/null; then
        ufw allow ${server_listen_port}/udp
    else
        echo "Warning: Neither firewalld nor ufw found. Please ensure UDP port ${server_listen_port} is open." >&2
    fi

    echo "WireGuard server initialized at $config_file"
    exit 0
fi

# --- Peer Management ---

# If no arguments, just report config exists
if [ $# -eq 0 ]; then
    echo "$config_file already exists."
    exit 0
fi

cmd="$1"
name="$2"

case "$cmd" in

add)
    # Add a new peer
    [[ -n "$name" ]] || err "User name is mandatory."
    grep -q "^# $name\$" "$config_file" && err "User $name already exists"

    # Get the server's public IP address
    get_public_ip
    server_ip=$(<"$server_dir/ipextern")
    ipv4_prefix="10.1.0."
    ipv4_mask="32"

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
            echo "AllowedIPs = ${ipv4_prefix}0/$ipv4_mask"
            echo "Endpoint = $server_ip:$server_listen_port"
        } >"$clients_dir/$name.conf"

        # Apply the new configuration
        wg syncconf "$wg_iface" <(wg-quick strip "$wg_iface")

        # Output the client config
        echo "########## START CONFIG ##########"
        cat "$clients_dir/$name.conf"
        echo "########### END CONFIG ###########"
        exit 0
    done

    err "No available peerIP address"
    ;;

remove)
    # Remove a peer
    [[ -n "$name" ]] || err "User name is mandatory."

    if grep -q "^# $name\$" "$config_file"; then
        rm -f "$clients_dir/$name.conf"
        # Remove peer block (from comment line to next blank line or EOF)
        sed -i "/^# $name\$/,/^$/d" "$config_file"
        wg syncconf "$wg_iface" <(wg-quick strip "$wg_iface")
        echo "User $name removed."
        exit 0
    else
        err "User $name does not exist."
    fi
    ;;

*)
    # Unknown command
    err "Unknown command '$cmd'. Use 'add' or 'remove'."
    ;;

esac
