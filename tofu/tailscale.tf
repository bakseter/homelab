provider "tailscale" {
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  tailnet             = "bakseter.github"
}

resource "tailscale_dns_split_nameservers" "domains" {
  for_each = toset([
    "bakseter.net",
    "int.bakseter.net",
    "sre.bakseter.net",
  ])

  domain      = each.key
  nameservers = ["100.113.132.29"] # infra
}
