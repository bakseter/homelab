terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }

    time = {
      source  = "hashicorp/time"
      version = "0.14.0"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }

    proxmox = {
      source  = "bpg/proxmox"
      version = "0.106.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}
