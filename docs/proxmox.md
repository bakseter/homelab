# Proxmox

Five nodes, each connected to a single Proxmox cluster:

- `m715q`
- `m715q2`
- `m720q`
- `m920q`
- `m70qg3`

## VMs

Each node runs a single controlplane VM and a single worker VM.
The only exceptions are `m715q` and `m70qg3`, which only run a single worker VM.

All VMs run Talos Linux. No other VMs exist; everything else should run inside the Kubernetes cluster.

## Ansible

Promox hosts are managed via Ansible, see [ansible/](../ansible/).
Not much is done there except configure things like `/etc/hosts` and network interfaces for VLANs.
