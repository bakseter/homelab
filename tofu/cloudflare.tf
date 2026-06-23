provider "cloudflare" {
  api_token = var.cloudflare_api_token
}


locals {
  envoy_gateway = "http://envoy-cloudflared-cloudflared-gateway-7fece151.envoy-gateway-system.svc.cluster.local:80"
  public_domains = [
    "bakseter.no",
    # # "bakseter.net",
    # "mandagsmiddag.no",
  ]
}


resource "cloudflare_zone" "domain" {
  for_each = toset(local.public_domains)

  account = {
    id = var.cloudflare_account_id
  }
  name = each.key
  type = "full"
}

resource "random_id" "homelab" {
  byte_length = 35
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  account_id    = var.cloudflare_account_id
  name          = "homelab"
  config_src    = "cloudflare"
  tunnel_secret = sensitive(random_id.homelab.b64_std)
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "token" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "config" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
  source     = "cloudflare"

  config = {
    ingress = []
  }
}

resource "cloudflare_dns_record" "tunnel" {
  for_each = toset(local.public_domains)

  zone_id = cloudflare_zone.domain[each.key].id
  name    = each.key
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}
