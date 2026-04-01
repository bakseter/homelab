# homelab

This repository contains everything needed to replicate the software side of my homelab.

Everything except for the OS install of Proxmox itsself is managed either via OpenTofu, Ansible or Argo CD.

## Components

- Proxmox VE is installed on (four, currently) bare metal servers.

- Ansible is used for configuring the Proxmox hosts. See the `/ansible` directory.

- OpenTofu is used to manage the Proxmox configuration, including VMs, storage,
  and networking. See the `tofu/` directory. VMs are running Talos Linux.

- After the Talos Linux cluster is bootstrapped and Cilium + Argo CD is installed,
  Argo CD is used to manage the rest of the configuration. See the `manifests/` directory.

## Technologies used

- Proxmox VE for virtualization
- Talos Linux for the VM OS
- OpenTofu and Ansible for infrastructure as code
- Argo CD for GitOps
- Cilium for networking and service mesh
- Longhorn for distributed block storage
- Prometheus, Grafana Operator, Loki and Grafana Alloy for monitoring
- Cloudflared + Traefik for exposing services externally
- Tailscale Operator for exposing services internally
- Keel for automatic image updates
- Sealed Secrets for managing secrets
- Cloudnative PG for PostgreSQL

## TODO

- [ ] Manage Cloudflare configuration with OpenTofu
- [ ] Manage Tailscale configuration with OpenTofu
