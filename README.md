# Absolutely easy wireguard

A straightforward and simple bash script to set up and start a WireGuard server, capable of adding and removing peers without needing to restart the WireGuard interface.Generates a minimalist config no DNS, no pre-shared key and only ipv4.

Requires `wireguard-tools`

## Usage

Without arguments, will create a new server configuration if there isn't one already.

`wg-server.sh add/remove peer_name`
