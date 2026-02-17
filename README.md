# homelab

This repository contains everything needed to replicate the software side of my homelab.

Everything except for the OS install of Proxmox itsself
is managed either via OpenTofu, (Ansible) or Argo CD.

...exceeeeept for the ones below (TODO):

- [ ] Cloudflare configuration (OpenTofu)
- [ ] Tailscale configuration (OpenTofu)
- [ ] Hetzner Cloud backup for Longhorn (OpenTofu)
- [ ] Misc. OS fixes for stubborn M720q ethernet controller (Ansible)

## Components

- Proxmox VE is installed on (three, currently) bare metal servers

- OpenTofu is used to manage the Proxmox configuration, including VMs, storage,
  and networking. See the `tofu/` directory. VMs are running Talos Linux.

- After the Talos Linux cluster is bootstrapped and Cilium + Argo CD is installed,
  Argo CD is used to manage the rest of the configuration. See the `manifests/` directory.

## Technologies used

- Proxmox VE for virtualization
- Talos Linux for the VM OS
- OpenTofu for infrastructure as code
- Argo CD for GitOps
- Cilium for networking and service mesh
- Longhorn for distributed block storage
- Prometheus, Grafana Operator, Loki and Grafana Alloy for monitoring
- Cloudflared + Traefik for exposing services externally
- Tailscale Operator for exposing services internally
- Keel for automatic image updates
- Sealed Secrets for managing secrets
- Cloudnative PG for PostgreSQL
