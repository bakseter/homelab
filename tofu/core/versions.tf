terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "3.3.1"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "0.14.1"
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
