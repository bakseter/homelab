# Compute

## Proxmox/Talos cluster

Proxmox cluster running only Talos VMs.
Each Proxmox node has 1-2 Talos VMs each.
There are always at least 3 controlplane VMs, split accros
the physical machines.

Rule of thumb is any workload should run inside Talos cluster as a Kubernetes pod.

### `m715q`

**OS**: Proxmox Virtual Environment

**CPU**: AMD Ryzen 3 PRO 2200GE (4 cores)

**RAM**: 24GB DDR4 2667Mhz SODIMM

**Boot drive**: 256GB NVMe SSD

**Data drive**: 500GB Samsung 870 EVO SSD

**NIC 1**: 1Gbe

**NIC 2**: 2.5Gbe

### `m715q2`

**OS**: Proxmox Virtual Environment

**Model**: Lenovo Thinkcentre M715q

**CPU**: AMD Ryzen 3 PRO 2200GE (4 cores)

**RAM**: 16GB DDR4 2666MHz SODIMM

**Boot drive**: 256GB Generic NVMe SSD

**Data drive**: 128GB Generic SATA SSD

**NIC 1**: 1Gbe

**NIC 2**: 2.5Gbe

### `m720q`

**OS**: Proxmox Virtual Environment

**Model**: Lenovo Thinkcentre M720q

**CPU**: Intel Core i5-8400T (6 cores)

**RAM**: 32GB DDR4 3200Mhz SODIMM

**Boot drive**: 256GB Generic NVMe SSD

**Data drive**: 500GB Samsung 870 EVO SSD

**NIC 1**: 1Gbe

**NIC 2**: 2.5Gbe

### `m920q`

**OS**: Proxmox Virtual Environment

**Model**: Lenovo Thinkcentre M720q

**CPU**: Intel Core i5-8500T (6 cores)

**RAM**: 32GB DDR4 2667Mhz SODIMM

**Boot drive**: 256GB Generic NVMe SSD

**Data drive**: 1TB Samsung 870 EVO SSD

**NIC 1**: 1Gbe

**NIC 2**: 2.5Gbe

### `m70qg3`

**OS**: Proxmox Virtual Environment

**Model**: Lenovo Thinkcentre M70q Gen 3

**CPU**: Intel Core i5-12400T (6 cores)

**RAM**: 32GB DDR4 3200MHz SODIMM

**Boot drive**: 256GB Generic NVMe SSD

**NIC 1**: 1Gbe

## Management node

Manages the rest of the homelab via OpenTofu and Ansible.
Has direct access to e.g. the Proxmox/Talos cluster and NAS VLANs.
Available via Tailscale only.

### `infra`

**OS**: NixOS

**Model**: Lenovo Thinkcentre M720q

**CPU**: Intel Core i3-8100T

**RAM**: 16 DDR4 2667 Mhz SODIMM

**Boot drive**: 120GB Generic Sata (?) SSD

**NIC**: 1Gbe

## NAS

Used as dedicated Kubernetes storage via NFS (democratic-csi).

### _untitled_

**OS**: TrueNAS

**Model**: Terramaster F-424

**CPU**: Intel Celeron N95 (4 cores)

**RAM**: 8GB DDR5 4800Mhz

**Drive 1**: 4TB Seagate IronWolf

**Drive 4 (Boot)**: 256GB Generic Sata SSD

**NIC 1**: 2.5Gbe

**NIC 2**: 2.5Gbe

## Backup DNS

Runs backup Technitium DNS server.
Available via Tailscale.

### `pi`

**OS**: Raspberry Pi OS Lite

**Model**: Rasbpberry Pi Model 3B+

# Networking

## Telia C1 Smart Router

Used only as modem, set to "bridge mode".

## Mikrotik hAP ax3

Main router, connected to modem.

## Mikrotik hAP ax S

Connected to main router via fiber, used as WiFi extender.

## TP-Link SG108E

Managed Gigabit switch, connected to main router via ethernet.
