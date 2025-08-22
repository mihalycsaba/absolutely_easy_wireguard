# Absolutely easy wireguard

A straightforward bash script to configure and manage a WireGuard server interface. Configures a point-to-point VPN tunnel, restricting peer access solely to the server. Peers cannot communicate with each other or use the server as a gateway for other traffic.

## Features
- Configures the WireGuard interface with client isolation (no peer-to-peer access)
- Direct server access only (no internet routing or subnet routing)
- Dynamic peer management without WireGuard interface restart
- Minimalist configuration (IPv4 only, no DNS, no pre-shared keys)
- Automatic server configuration generation

## Requirements
- `wireguard-tools`

## Usage
Without arguments, creates a new server configuration if none exists and brings up the WireGuard interface:
```bash
./wg-server.sh
```

To manage peers:
```bash
./wg-server.sh add peer_name
./wg-server.sh remove peer_name
```
