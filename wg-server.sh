#!/bin/bash

set -euo pipefail

display_usage() {
    cat <<EOF
Usage:
  $(basename "$0")                # Initialize new server config if missing
  $(basename "$0") add <peer>     # Add a WireGuard peer with name <peer>
  $(basename "$0") remove <peer>  # Remove a WireGuard peer with name <peer>
  $(basename "$0") --help         # Show this help message
EOF
}

err() { echo "ERROR: $*" >&2; exit 1; }

require_root() {
    [ "$(id -u)" = "0" ] || err "root is required to configure WireGuard"
}

require_cmd() {
    command -v "$1" &>/dev/null || err "'$1' command not found, please install it."
}

# ---- MAIN ----

wg_iface="wg0"
config_file="/etc/wireguard/${wg_iface}.conf"
server_dir="/etc/wireguard/server"
clients_dir="/etc/wireguard/clients"

if [[ "${1:-}" == "--help" ]]; then
    display_usage
    exit 0
fi

require_root
require_cmd wg

if [ ! -f "$config_file" ]; then
    # --- Server Initialization ---
    install -d -m 700 /etc/wireguard
    install -d -m 700 "$server_dir" "$clients_dir"

    curl -fsSL https://api.ipify.org >"$server_dir/ipextern" || err "Failed to fetch public IP"

    wg genkey | tee "$server_dir/server.key" >/dev/null
    server_privkey=$(<"$server_dir/server.key")

    cat >"$config_file" <<EOM
[Interface]
# WireGuard interface will be run at 10.1.0.0
Address = 10.1.0.0/24
PrivateKey = $server_privkey
ListenPort = 51820

EOM

    if command -v systemctl &>/dev/null; then
        systemctl enable --now "wg-quick@$wg_iface"
    fi

    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port=51820/udp --zone=public
        firewall-cmd --reload
    fi

    echo "WireGuard server initialized at $config_file"
    exit 0
fi

# --- Peer Management ---

if [ $# -eq 0 ]; then
    echo "$config_file already exists."
    exit 0
fi

cmd="$1"
name="${2:-}"

case "$cmd" in

add)
    [[ -n "$name" ]] || err "User name is mandatory."
    grep -q "^# $name\$" "$config_file" && err "User $name already exists"

    curl -fsSL https://api.ipify.org >"$server_dir/ipextern" || err "Failed to fetch public IP"
    server_ip=$(<"$server_dir/ipextern")
    server_port=51820
    ipv4_prefix="10.1.0."
    ipv4_mask="32"

    server_privkey=$(<"$server_dir/server.key")
    server_pubkey=$(echo -n "$server_privkey" | wg pubkey)

    client_privkey=$(wg genkey)
    client_pubkey=$(echo -n "$client_privkey" | wg pubkey)

    # Find available IPv4 for peer
    for client_number in $(seq 1 255); do
        client_ipv4="${ipv4_prefix}${client_number}/${ipv4_mask}"
        grep -q "$client_ipv4" "$config_file" && continue

        {
            echo
            echo "# $name"
            echo "[Peer]"
            echo "PublicKey = $client_pubkey"
            echo "AllowedIPs = $client_ipv4"
        } >>"$config_file"

        cat >"$clients_dir/$name.conf" <<EOM
[Interface]
PrivateKey = $client_privkey
Address = $client_ipv4

[Peer]
PublicKey = $server_pubkey
AllowedIPs = ${ipv4_prefix}0/$ipv4_mask
Endpoint = $server_ip:$server_port
EOM

        wg syncconf "$wg_iface" <(wg-quick strip "$wg_iface")

        echo "########## START CONFIG ##########"
        cat "$clients_dir/$name.conf"
        echo "########### END CONFIG ###########"
        exit 0
    done

    err "No available IPv4 address"
    ;;

remove)
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
    err "Unknown command '$cmd'. Use 'add' or 'remove'."
    ;;

esac
