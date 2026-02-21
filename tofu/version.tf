terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }

    time = {
      source = "hashicorp/time"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.9"
    }

    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.96"
    }

    null = {
      source = "hashicorp/null"
    }
  }
}
