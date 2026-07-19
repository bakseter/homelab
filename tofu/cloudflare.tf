provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  envoy_gateway = "http://envoy-cloudflared-cloudflared-60c155f1.envoy-gateway-system.svc.cluster.local:80"
  domains = [
    "bakseter.net"
  ]
  public_domains = [
    "bakseter.no",
    "mandagsmiddag.no",
  ]
  all_domains = concat(local.domains, local.public_domains)
}


## DNS zones

resource "cloudflare_zone" "domain" {
  for_each = toset(local.all_domains)

  account = {
    id = var.cloudflare_account_id
  }
  name = each.key
  type = "full"
}

resource "cloudflare_zone_setting" "always-use-https" {
  for_each = toset(local.all_domains)

  zone_id    = cloudflare_zone.domain[each.key].id
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "tls-1-3" {
  for_each = toset(local.all_domains)

  zone_id    = cloudflare_zone.domain[each.key].id
  setting_id = "tls_1_3"
  value      = "zrt"
}

resource "cloudflare_zone_setting" "security-header" {
  for_each = toset(local.all_domains)

  zone_id    = cloudflare_zone.domain[each.key].id
  setting_id = "security_header"
  value = {
    strict_transport_security = {
      enabled            = true
      include_subdomains = true
      max_age            = 15552000
      nosniff            = true
      preload            = true
    }
  }
}


## Tunnel

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
    ingress = concat(
      flatten(
        [for domain in local.public_domains :
          [
            {
              hostname       = "*.${domain}"
              origin_request = {}
              service        = local.envoy_gateway
            },
            {
              hostname       = domain
              origin_request = {}
              service        = local.envoy_gateway
            }
          ]
        ]
      ),
      [{ service = "http_status:404" }]
    )
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


## Email

resource "cloudflare_dns_record" "bakseter-no-email-cname" {
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

resource "cloudflare_dns_record" "bakseter-no-email-mx" {
  for_each = tomap({
    "mail.protonmail.ch"    = 10,
    "mailsec.protonmail.ch" = 20,
  })

  zone_id  = cloudflare_zone.domain["bakseter.no"].id
  name     = "bakseter.no"
  content  = each.key
  type     = "MX"
  ttl      = 1
  proxied  = false
  priority = each.value
}

resource "cloudflare_dns_record" "bakseter-no-email-txt" {
  for_each = tomap({
    "\"protonmail-verification=fa6fb8716c3cdce363ac0e8ad66946e85fcec662\"" = "bakseter.no"
    "\"v=spf1 include:_spf.protonmail.ch ~all\""                           = "bakseter.no"
    "\"v=DMARC1; p=quarantine\""                                           = "_dmarc.bakseter.no"
  })

  zone_id = cloudflare_zone.domain["bakseter.no"].id
  name    = each.value
  content = each.key
  type    = "TXT"
  ttl     = 1
  proxied = false
}


## Security rules

resource "cloudflare_ruleset" "mandagsmiddag-geoip-block" {
  zone_id     = cloudflare_zone.domain["mandagsmiddag.no"].id
  name        = "GeoIP Allow List Rule"
  description = "Block all traffic except allowed countries"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = [
    {
      action      = "block"
      description = "Block non-allowed countries"
      expression  = "not ip.src.country in {\"NO\"}"
      enabled     = true
    }
  ]
}


## Bot management

resource "cloudflare_bot_management" "domain" {
  for_each = toset(local.public_domains)

  zone_id               = cloudflare_zone.domain[each.key].id
  fight_mode            = true
  enable_js             = true
  ai_bots_protection    = "block"
  is_robots_txt_managed = true
  crawler_protection    = "enabled"
}
