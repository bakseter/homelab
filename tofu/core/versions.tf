terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "3.3.2"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }

    time = {
      source  = "hashicorp/time"
      version = "0.14.2"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0-rc.0"
    }

    proxmox = {
      source  = "bpg/proxmox"
      version = "0.113.1"
    }
  }
}
