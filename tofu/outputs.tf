output "authentik_argocd_client_secret" {
  value     = authentik_provider_oauth2.argocd.client_secret
  sensitive = true
}

output "authentik_grafana_client_secret" {
  value     = authentik_provider_oauth2.grafana.client_secret
  sensitive = true
}

output "authentik_vaultwarden_client_secret" {
  value     = authentik_provider_oauth2.vaultwarden.client_secret
  sensitive = true
}
