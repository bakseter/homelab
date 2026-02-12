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
      version = "~> 0.10"
    }

    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.89"
    }

    null = {
      source = "hashicorp/null"
    }
  }
}
