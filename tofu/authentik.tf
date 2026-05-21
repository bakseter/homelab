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


# APPLICATION AUTH

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


# OIDC INTEGRATIONS

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

resource "authentik_provider_oauth2" "argocd" {
  name               = "argocd"
  client_id          = "argocd"
  authorization_flow = data.authentik_flow.default-provider-authorization-explicit-consent.id
  invalidation_flow  = data.authentik_flow.default-provider-invalidation-flow.id
  sub_mode           = "user_username"
  signing_key        = data.authentik_certificate_key_pair.default.id
  property_mappings  = data.authentik_property_mapping_provider_scope.scopes.ids
  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://argocd.sre.bakseter.net/api/dex/callback"
    }
  ]
}

resource "authentik_application" "argocd" {
  name              = "Argo CD"
  slug              = "argocd"
  protocol_provider = authentik_provider_oauth2.argocd.id
}


# RBAC

data "authentik_user" "andreas" {
  pk = "17"
}

data "authentik_user" "emil" {
  pk = "19"
}

resource "authentik_group" "argocd-admins" {
  name  = "argocd-admins"
  users = [data.authentik_user.andreas.id]
}

import {
  id = "7250ff1d-6a53-42c5-a18f-8866e1a2b84b"
  to = authentik_group.mandagsmiddag-admins
}

resource "authentik_group" "mandagsmiddag-admins" {
  name = "mandagsmiddag-admins"
  users = [
    data.authentik_user.andreas.id,
    data.authentik_user.emil.id,
  ]
}
