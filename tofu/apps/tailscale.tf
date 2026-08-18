provider "tailscale" {
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  tailnet             = "bakseter.github"
}

locals {
  technitium_tailscale_ips = [
    "100.85.36.251", # k8s
    "100.88.208.56", # pi
  ]
  tailscale_domains = [
    "bakseter.net",
    "int.bakseter.net",
    "sre.bakseter.net",
  ]
}

resource "tailscale_dns_nameservers" "global" {
  nameservers = concat(
    local.technitium_tailscale_ips,
    [
      "1.1.1.1",
      "8.8.8.8",
    ]
  )
}

resource "tailscale_dns_split_nameservers" "domains" {
  for_each = toset(local.tailscale_domains)

  domain      = each.key
  nameservers = local.technitium_tailscale_ips
}
