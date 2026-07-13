terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2026.5.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.22.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "3.3.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
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
      version = "0.111.1"
    }
  }
}
