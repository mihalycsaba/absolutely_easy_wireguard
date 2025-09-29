# Absolutely Easy WireGuard

A simple Bash script to configure and manage a WireGuard server interface for point-to-point VPN tunnels. Each peer can only access the server; peers cannot communicate with each other or use the server as a gateway for other traffic.

## Features

- **Client isolation:** Peers cannot access each other, only the server.
- **No internet or subnet routing:** Only direct server access is allowed.
- **Dynamic peer management:** Add or remove peers without restarting the WireGuard interface.
- **Zero downtime client management:** Peer changes are applied instantly without interrupting existing connections.
- **Minimal configuration:** IPv4 only, no DNS, no pre-shared keys.
- **Firewall integration:** Attempts to open the WireGuard port using `firewalld` or `ufw`.
- **Systemd support:** Enables and starts the WireGuard service if `systemctl` is available.

## Requirements

- `wireguard-tools`
- `curl` (for public IP detection)
- Root privileges

## Usage

Initialize the server (creates config if missing and brings up the interface):

```bash
sudo ./wg-server.sh
```

Add a peer:

```bash
sudo ./wg-server.sh -a <peer_name>
```

Remove a peer:

```bash
sudo ./wg-server.sh -r <peer_name>
```

List all peers:

```bash
sudo ./wg-server.sh -l
```

Show help:

```bash
./wg-server.sh -h
```

## Configuration

- By default, the server uses `10.1.0.0/24` as its subnet and listens on UDP port `51820`.
- You can change these values by editing the `wg_address` and `wg_listen_port` variables at the top of `wg-server.sh`.
- The server's public IP is automatically detected **only if** the `server_ip` variable is left empty. This logic is handled inside the `get_public_ip` function in the script.

## How it works

- Server and client keys are generated automatically and stored in `/etc/wireguard/server` and `/etc/wireguard/clients`.
- Client configuration files are created in `/etc/wireguard/clients/<peer_name>.conf`.
- The script uses the first available IP in the `10.1.0.0/24` subnet for each new peer.
- The public IP detection only runs if `server_ip` is empty, so you can set a static IP by assigning a value to `server_ip` at the top of the script.
- Peers are managed dynamically using `wg syncconf` and `wg-quick strip` for zero-downtime updates.

## Notes

- The script must be run as root.
- Ensure UDP port `51820` is open on your firewall. The script tries to configure this automatically if `firewalld` or `ufw` is present.
- Only IPv4 is supported.
- No DNS or pre-shared keys are configured for simplicity.

---
