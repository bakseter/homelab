terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }

    time = {
      source  = "hashicorp/time"
      version = "0.13.1"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "0.10.1"
    }

    proxmox = {
      source  = "bpg/proxmox"
      version = "0.105.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}
