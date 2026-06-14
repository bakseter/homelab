# Proxmox

Four nodes, each connected to a single Proxmox cluster:

- m715q
- m715q2
- m720q
- m920q

## VMs

Each node runs a single controlplane VM and a single worker VM.
The only exception is `m715q`, which only runs a single worker VM.

All VMs run Talos Linux. No other VMs exist; everything else should run inside the Kubernetes cluster.

## Ansible

Promox hosts are managed via Ansible, see [ansible/](../ansible/).
Not much is done there except configure things like `/etc/hosts` and network interfaces for VLANs.
