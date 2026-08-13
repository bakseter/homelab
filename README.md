# homelab 🏡🚀

This repository contains (almost) everything needed to replicate the software side of my homelab.

Most, if not all, of the components are managed by Infrastructure-as-Code.

See `docs/` for more information.

## TL;DR

- Proxmox VE is manually installed on each physical host, bare metal.

- Ansible is used for configuring the Proxmox hosts. See the `ansible/` directory.

- OpenTofu is used to manage the Proxmox configuration, including VMs, storage,
  and networking. Proxmox VMs are running Talos Linux. See the `tofu/` directory.

- After the Talos Linux cluster is bootstrapped and Cilium + Argo CD is installed,
  Argo CD is used to manage the rest of the configuration. See the `manifests/` directory.

## What's running?

As a platform engineer, Kubernetes-lover and Cloud Native-enthusiast, I'm mostly running
Linux/CNCF-related technologies I either already know and love, or ones I want to test out privately.

_(list might not be 100% up to date)_

### Infrastructure

- **NixOS** as management node OS
- **Ansible** for managing bare-metal clients
- **OpenTofu** for infrastructure management
- **Proxmox VE** for virtualization platform
- **Talos Linux** as Kubernetes node OS

### Core Kubernetes services

- **Cilium** as CNI
- **Argo CD** for GitOps
- **Sealed Secrets** for secret management
- **Longhorn** for block storage
- **RustFS** for S3 storage
- **democratic-csi** and **TrueNAS** for NFS storage
- **Velero** for backups
- **Loki**, **Grafana Operator**, **Tempo**, **Prometheus**, **Alertmanager** and **Pushover** for monitoring
- **Authentik** as authentication provider
- **cloudflared** for public access
- **Tailscale Operator** for private access
- **Envoy Gateway** with **Gateway API** for routing from Cloudflare/Tailscale to workloads
- **cert-manager** for certificates
- **Technitium** and **external-dns** for private DNS with Tailscale
- **Cloudnative-PG** for PostgreSQL
- **Forgejo** for private git and private CI/CD
- **Harbor** and **Trivy** for image pull-trough cache and scanning
- **`registry:3`** for private container registry

### Third-party services

- **Cloudflare** for domains, DNS and tunnels
- **GitHub** for public git and CI/CD (duh)
- **Tailscale** for private access platform
- **Hetzner Cloud** for Longhorn and Velero backups
- **Pushover** for alerts from monitoring stack

### Apps

- **Immich** for photos
- **Jellyfin**, **Seerr**, **Radarr**, **Sonarr**, **Lidarr**, **Prowlarr** and **sabnzbd** for media management
- **Audiobookshelf** for podcasts
- **Vaultwarden** for password management
- **Homepage** for landing page
- **Cryptpad** for office suite

### Hobby projects

- [bakseter.no](https://bakseter.no)
- [Mandagsmiddag](https://github.com/bakseter/mandagsmiddag)
- [AMEX](https://github.com/bakseter/amex)
- [five31](https://github.com/bakseter/five31)
