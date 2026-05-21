# Setup
#
# 1. Configure Authentik instance with public URL.
# 2. Go to Admin interface -> Directory -> Tokens and App password.
#    Create an API Token on the default user 'akadmin'.
# 3. Paste URL and token into Tofu vars.

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}

data "authentik_flow" "default-provider-authorization-implicit-consent" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default-provider-authorization-explicit-consent" {
  slug = "default-provider-authorization-explicit-consent"
}

data "authentik_flow" "default-provider-invalidation-flow" {
  slug = "default-provider-invalidation-flow"
}

resource "authentik_provider_proxy" "mandagsmiddag-frontend" {
  name                  = "mandagsmiddag-frontend"
  external_host         = "https://mandagsmiddag.no"
  authorization_flow    = data.authentik_flow.default-provider-authorization-explicit-consent.id
  invalidation_flow     = data.authentik_flow.default-provider-invalidation-flow.id
  access_token_validity = "hours=24"
  mode                  = "forward_single"
}

resource "authentik_provider_proxy" "mandagsmiddag-backend" {
  name                  = "mandagsmiddag-backend"
  external_host         = "https://mandagsmiddag.no/api"
  authorization_flow    = data.authentik_flow.default-provider-authorization-explicit-consent.id
  invalidation_flow     = data.authentik_flow.default-provider-invalidation-flow.id
  access_token_validity = "hours=24"
  mode                  = "forward_single"
}

resource "authentik_application" "mandagsmiddag-backend" {
  name              = "mandagsmiddag-backend"
  slug              = "mandagsmiddag-backend"
  protocol_provider = authentik_provider_proxy.mandagsmiddag-backend.id
}


data "authentik_service_connection_kubernetes" "local" {
  name = "Local Kubernetes Cluster"
}

resource "authentik_outpost" "mandagsmiddag" {
  name = "mandagsmiddag"
  protocol_providers = [
    authentik_provider_proxy.mandagsmiddag-frontend.id,
    authentik_provider_proxy.mandagsmiddag-backend.id,
  ]
  service_connection = data.authentik_service_connection_kubernetes.local.id

  config = jsonencode(
    {
      authentik_host                   = "https://authentik.bakseter.net/"
      authentik_host_browser           = ""
      authentik_host_insecure          = false
      container_image                  = null
      docker_labels                    = null
      docker_map_ports                 = true
      docker_network                   = null
      kubernetes_disabled_components   = []
      kubernetes_httproute_annotations = {}
      kubernetes_httproute_parent_refs = []
      kubernetes_image_pull_secrets    = []
      kubernetes_ingress_annotations   = {}
      kubernetes_ingress_class_name    = null
      kubernetes_ingress_path_type     = null
      kubernetes_ingress_secret_name   = ""
      kubernetes_json_patches = {
        deployment = [
          {
            op   = "add"
            path = "/spec/template/spec/containers/0/resources"
            value = {
              limits = {
                cpu    = "100m"
                memory = "256Mi"
              }
              requests = {
                cpu    = "10m"
                memory = "64Mi"
              }
            }
          },
        ]
        ingress = [
          {
            op   = "remove"
            path = "/spec/rules/1"
          },
        ]
      }
      kubernetes_namespace    = "authentik"
      kubernetes_replicas     = 1
      kubernetes_service_type = "ClusterIP"
      log_level               = "info"
      object_naming_template  = "ak-outpost-%(name)s"
      refresh_interval        = "minutes=5"
    }
  )
}

resource "authentik_provider_proxy" "argocd" {
  name               = "argocd"
  external_host      = "https://argocd.sre.bakseter.net"
  authorization_flow = data.authentik_flow.default-provider-authorization-explicit-consent.id
  invalidation_flow  = data.authentik_flow.default-provider-invalidation-flow.id
  mode               = "forward_single"
}

resource "authentik_application" "argocd" {
  name              = "Argo CD"
  slug              = "argocd"
  protocol_provider = authentik_provider_proxy.argocd.id
}

resource "authentik_outpost" "envoy-gateway-sre" {
  name               = "envoy-gateway-sre-outpost"
  type               = "proxy"
  service_connection = data.authentik_service_connection_kubernetes.local.id
  protocol_providers = [
    authentik_provider_proxy.argocd.id,
  ]
  config = jsonencode({
    authentik_host          = "https://authentik.bakseter.net"
    authentik_host_insecure = false
    kubernetes_replicas     = 1
    kubernetes_namespace    = "authentik"
  })
}
