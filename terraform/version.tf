terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }

    time = {
      source = "hashicorp/time"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.8"
    }

    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78"
    }
  }
}
