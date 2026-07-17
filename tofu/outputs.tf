output "authentik_argocd_client_secret" {
  value     = authentik_provider_oauth2.argocd.client_secret
  sensitive = true
}

output "authentik_grafana_client_secret" {
  value     = authentik_provider_oauth2.grafana.client_secret
  sensitive = true
}

output "authentik_five31_client_secret" {
  value     = authentik_provider_oauth2.five31.client_secret
  sensitive = true
}

output "authentik_mandagsmiddag_client_secret" {
  value     = authentik_provider_oauth2.mandagsmiddag.client_secret
  sensitive = true
}
