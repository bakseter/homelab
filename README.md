# homelab 🏡🚀

This repository contains everything needed to replicate the software side of my homelab.

Most, if not all, of the components are managed by Infrastructure-as-Code.

See `docs/` for more information.

## Overview

- Proxmox VE is manually installed on bare metal servers.

- Ansible is used for configuring the Proxmox hosts. See the `ansible/` directory.

- OpenTofu is used to manage the Proxmox configuration, including VMs, storage,
  and networking. VMs are running Talos Linux. See the `tofu/` directory.

- After the Talos Linux cluster is bootstrapped and Cilium + Argo CD is installed,
  Argo CD is used to manage the rest of the configuration. See the `manifests/` directory.
