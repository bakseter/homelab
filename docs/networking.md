# Networking

## VLANs

### `10` - management

Router and Proxmox hosts.

### `20` - cluster

Proxmox cluster (corosync).

### `30` - talos

Talos VMs.

### `40` - gaming (dhcp)

Reserved for gaming desktop (no VPN).

### `50` - wifi (dhcp)

Everything connected to WiFi: laptops, phones, etc..

### `60` - infra (dhcp)

For single management machine, gets access to all VLANs.
This means to access router, you must SSH to this node.

### `70` - storage (dhcp)

NAS.

### `80` - media (dhcp)

Media players (no VPN).
