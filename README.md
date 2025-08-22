# Absolutely easy wireguard

A straightforward and simple bash script to set up and start a WireGuard server. This will allow you to access your server and only your server through wg. It can add and remove peers without needing to restart the wg interface. Generates a minimalist config no DNS, no pre-shared key and only ipv4.

Requires `wireguard-tools`

## Usage

Without arguments, will create a new server configuration if there isn't one already.

`wg-server.sh add/remove peer_name`
