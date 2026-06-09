terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }

    authentik = {
      source  = "goauthentik/authentik"
      version = "2026.2.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "0.14.0"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }

    proxmox = {
      source  = "bpg/proxmox"
      version = "0.109.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "3.3.0"
    }
  }
}
