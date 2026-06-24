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

## Email

resource "cloudflare_dns_record" "email-cname" {
  for_each = tomap({
    "protonmail._domainkey.bakseter.no" : "protonmail.domainkey.dy24vvdj7a2bqr5hvsxwoc7qfhmnk522sw5rmc34ynnoo45ncfp6a.domains.proton.ch",
    "protonmail2._domainkey.bakseter.no" : "protonmail2.domainkey.dy24vvdj7a2bqr5hvsxwoc7qfhmnk522sw5rmc34ynnoo45ncfp6a.domains.proton.ch",
    "protonmail3._domainkey.bakseter.no" : "protonmail3.domainkey.dy24vvdj7a2bqr5hvsxwoc7qfhmnk522sw5rmc34ynnoo45ncfp6a.domains.proton.ch",
  })

  zone_id = cloudflare_zone.domain["bakseter.no"].id
  name    = each.key
  content = each.value
  type    = "CNAME"
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "email-mx" {
  for_each = tomap({
    "bakseter.no" : "mail.protonmail.ch",
    "bakseter.no" : "mailsec.protonmail.ch",
  })

  zone_id = cloudflare_zone.domain["bakseter.no"].id
  name    = each.key
  content = each.value
  type    = "MX"
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "email-txt" {
  for_each = tomap({
    "bakseter.no" : "protonmail-verification=fa6fb8716c3cdce363ac0e8ad66946e85fcec662",
    "bakseter.no" : "v=spf1 include:_spf.protonmail.ch ~all",
    "bakseter.no" : "v=DMARC1; p=quarantine",
  })

  zone_id = cloudflare_zone.domain["bakseter.no"].id
  name    = each.key
  content = each.value
  type    = "TXT"
  ttl     = 1
  proxied = false
}
