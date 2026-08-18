terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2026.5.1"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.23.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }
  }
}
