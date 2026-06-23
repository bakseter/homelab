provider "cloudflare" {
  api_token = var.cloudflare_api_token
}


locals {
  envoy_gateway = "http://envoy-cloudflared-cloudflared-gateway-7fece151.envoy-gateway-system.svc.cluster.local:80"
  public_domains = [
    "bakseter.net",
    # "bakseter.no",
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

resource "random_id" "tunnel-secret" {
  for_each = toset(local.public_domains)

  byte_length = 35
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "tunnel" {
  for_each = toset(local.public_domains)

  account_id    = var.cloudflare_account_id
  name          = each.key
  config_src    = "cloudflare"
  tunnel_secret = random_id.tunnel-secret[each.key].b64_std
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "token" {
  for_each = toset(local.public_domains)

  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.tunnel[each.key].id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "config" {
  for_each = toset(local.public_domains)

  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.tunnel[each.key].id
  source     = "cloudflare"

  config = {
    ingress = [
      {
        hostname = each.key
        service  = local.envoy_gateway
      },
      {
        hostname = "*.${each.key}"
        service  = local.envoy_gateway
      },
      { service = "http_status:404" }
    ]
  }
}

resource "cloudflare_dns_record" "tunnel" {
  for_each = toset(local.public_domains)

  zone_id = cloudflare_zone.domain[each.key].id
  name    = each.key
  content = "${cloudflare_zero_trust_tunnel_cloudflared.tunnel[each.key].id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}
