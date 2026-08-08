provider "tailscale" {
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  tailnet             = "bakseter.github"
}

locals {
  tailscale_domains = [
    "bakseter.net",
    "int.bakseter.net",
    "sre.bakseter.net",
  ]
}

resource "tailscale_dns_nameservers" "global" {
  nameservers = "100.85.36.251" # k8s technitium
}

resource "tailscale_dns_split_nameservers" "domains" {
  for_each = toset(local.tailscale_domains)

  domain      = each.key
  nameservers = tailscale_dns_nameservers.global.nameservers
}
