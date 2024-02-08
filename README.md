# Absolutely easy wireguard

A straightforward and simple bash script to set up and start a WireGuard server, capable of adding and removing peers without needing to restart the WireGuard interface. Minimalist config no DNS, pre-shared key and only ipv4 (maybe ipv6 in the future).

Requires `wireguard-tools`

## Usage

Without arguments, will create a new server configuration if there isn't one already.

`wg-server.sh add/remove peer_name`
