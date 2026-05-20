provider "tailscale" {
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  tailnet             = "bakseter.github"
}

resource "tailscale_dns_split_nameservers" "bakseter-net" {
  domain      = "bakseter.net"
  nameservers = ["100.x.x.x"]
}
