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
      authentik_host = "https://authentik.bakseter.net"
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

data "authentik_property_mapping_provider_scope" "scopes" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-profile",
    "goauthentik.io/providers/oauth2/scope-email",
  ]
}

data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

resource "authentik_provider_oauth2" "envoy-gateway-sre" {
  name               = "envoy-gateway-sre"
  client_id          = "envoy-gateway-sre"
  authorization_flow = data.authentik_flow.default-provider-authorization-explicit-consent.id
  invalidation_flow  = data.authentik_flow.default-provider-invalidation-flow.id
  sub_mode           = "user_username"
  signing_key        = data.authentik_certificate_key_pair.default.id
  property_mappings  = data.authentik_property_mapping_provider_scope.scopes.ids
  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://argocd.sre.bakseter.net/oauth2/callback"
    }
  ]
}

resource "authentik_application" "envoy-gateway-sre" {
  name              = "Envoy Gateway sre"
  slug              = "envoy-gateway-sre"
  protocol_provider = authentik_provider_oauth2.envoy-gateway-sre.id
}
