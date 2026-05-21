output "authentik_envoy_gateway_sre_client_secret" {
  value     = authentik_provider_oauth2.envoy-gateway-sre.client_secret
  sensitive = true
}
