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
      version = "0.10.1"
    }

    proxmox = {
      source  = "bpg/proxmox"
      version = "0.100.0"
    }

    null = {
      source = "hashicorp/null"
    }
  }
}
