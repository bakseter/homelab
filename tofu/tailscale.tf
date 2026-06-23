provider "tailscale" {
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  tailnet             = "bakseter.github"
}

locals {
  technitium_tailscale_ips = toset([
    "100.85.36.251", # k8s
    "100.88.208.56", # pi
  ])

  domains = toset([
    "bakseter.net",
    "int.bakseter.net",
    "sre.bakseter.net",
  ])
}

resource "tailscale_dns_nameservers" "global" {
  nameservers = setunion(
    local.technitium_tailscale_ips,
    toset([
      "1.1.1.1",
    ])
  )
}

resource "tailscale_dns_split_nameservers" "domains" {
  for_each = local.domains

  domain      = each.key
  nameservers = local.technitium_tailscale_ips
}
