provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  envoy_gateway = "http://envoy-cloudflared-cloudflared-gateway-7fece151.envoy-gateway-system.svc.cluster.local:80"
  public_domains = [
    "bakseter.no",
    "bakseter.net",
    "mandagsmiddag.no",
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

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  account_id = var.cloudflare_account_id
  name       = "homelab"
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "token" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
  source     = "cloudflare"

  config = {
    ingress = [
      {
        hostname       = "bakseter.net"
        origin_request = {}
        service        = local.envoy_gateway
      },
      {
        hostname       = "authentik.bakseter.net"
        origin_request = {}
        service        = local.envoy_gateway
      },
      {
        hostname       = "*.mandagsmiddag.no"
        origin_request = {}
        service        = local.envoy_gateway
      },
      {
        hostname       = "mandagsmiddag.no"
        origin_request = {}
        service        = local.envoy_gateway
      },
      {
        hostname       = "*.bakseter.no"
        origin_request = {}
        service        = local.envoy_gateway
      },
      {
        hostname       = "bakseter.no"
        origin_request = {}
        service        = local.envoy_gateway
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

resource "cloudflare_dns_record" "tunnel-apex" {
  for_each = toset(local.public_domains)

  zone_id = cloudflare_zone.domain[each.key].id
  name    = each.key
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "tunnel-wildcard" {
  for_each = toset(["bakseter.no", "mandagsmiddag.no"])

  zone_id = cloudflare_zone.domain[each.key].id
  name    = "*.${each.key}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "authentik" {
  zone_id = cloudflare_zone.domain["bakseter.net"].id
  name    = "authentik.bakseter.net"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}
