#!/bin/bash

set -e
wg_iface="wg0"

# Params
name="$1"

# if name empty then exit
if [ -z "$1" ]; then
    echo "User name is mandatory."
    exit 1
fi

# Require root to change wg-related settings
if ! [ "$(id -u)" = "0" ]; then
    echo "ERROR: root is required to configure WireGuard clients"
    exit 1
fi

# Remove peer from config if it exists
if grep -q "$name" "/etc/wireguard/$wg_iface.conf"; then
    rm /etc/wireguard/clients/$name.conf
    sed -i "/^# $name/,/^$/d" /etc/wireguard/$wg_iface.conf
    wg syncconf $wg_iface <(wg-quick strip $wg_iface)
else
    echo "User $name does not exist."
fi
