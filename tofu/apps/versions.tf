terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2026.8.2"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.29.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.3"
    }
  }
}
