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

data "authentik_flow" "default-provider-invalidation-flow" {
  slug = "default-provider-invalidation-flow"
}


#### Application auth

# TODO: remove
resource "authentik_provider_proxy" "mandagsmiddag-frontend" {
  name                  = "mandagsmiddag-frontend"
  external_host         = "https://mandagsmiddag.no"
  authorization_flow    = data.authentik_flow.default-provider-authorization-implicit-consent.id
  invalidation_flow     = data.authentik_flow.default-provider-invalidation-flow.id
  access_token_validity = "hours=24"
  mode                  = "forward_single"
}

# TODO: remove
resource "authentik_provider_proxy" "mandagsmiddag-backend" {
  name                  = "mandagsmiddag-backend"
  external_host         = "https://mandagsmiddag.no/api"
  authorization_flow    = data.authentik_flow.default-provider-authorization-implicit-consent.id
  invalidation_flow     = data.authentik_flow.default-provider-invalidation-flow.id
  access_token_validity = "hours=24"
  mode                  = "forward_single"
}

# TODO: remove
resource "authentik_application" "mandagsmiddag-frontend" {
  name              = "Mandagsmiddag"
  slug              = "mandagsmiddag-frontend"
  protocol_provider = authentik_provider_proxy.mandagsmiddag-frontend.id

  meta_icon = "https://mandagsmiddag.no/icon.png"
}

# TODO: remove
resource "authentik_application" "mandagsmiddag-backend" {
  name              = "mandagsmiddag-backend"
  slug              = "mandagsmiddag-backend"
  protocol_provider = authentik_provider_proxy.mandagsmiddag-backend.id

  # Setting "Hide from application dashboard" not supported in Terraform.
  # https://docs.goauthentik.io/add-secure-apps/applications/manage_apps/#hide-applications
  meta_launch_url = "blank://blank"
}


#### OIDC integrations

# TODO: remove
data "authentik_service_connection_kubernetes" "local" {
  name = "Local Kubernetes Cluster"
}

# TODO: remove
resource "authentik_outpost" "mandagsmiddag" {
  name = "mandagsmiddag"
  protocol_providers = [
    authentik_provider_proxy.mandagsmiddag-frontend.id,
    authentik_provider_proxy.mandagsmiddag-backend.id,
  ]
  service_connection = data.authentik_service_connection_kubernetes.local.id

  config = jsonencode(
    {
      authentik_host         = "https://authentik.bakseter.no"
      log_level              = "info"
      object_naming_template = "ak-outpost-%(name)s"
      refresh_interval       = "minutes=5"

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
        ],

        httproute = [
          {
            op   = "remove"
            path = "/spec/rules/1"
          },
          {
            op   = "remove"
            path = "/spec/hostnames/1"
          }
        ]
      }
      kubernetes_namespace    = "authentik"
      kubernetes_replicas     = 1
      kubernetes_service_type = "ClusterIP"
      kubernetes_disabled_components = [
        "ingress",
        "traefik middleware",
      ]
      kubernetes_httproute_parent_refs = [
        {
          group     = "gateway.networking.k8s.io"
          kind      = "Gateway"
          name      = "cloudflared-gateway"
          namespace = "cloudflared"
        }
      ]
    }
  )
}

data "authentik_property_mapping_provider_scope" "scopes" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-profile",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-entitlements",
  ]
}

data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}


### Argo CD

resource "authentik_provider_oauth2" "argocd" {
  name      = "argocd"
  client_id = "argocd"

  authorization_flow = data.authentik_flow.default-provider-authorization-implicit-consent.id
  invalidation_flow  = data.authentik_flow.default-provider-invalidation-flow.id

  sub_mode = "user_username"

  signing_key       = data.authentik_certificate_key_pair.default.id
  property_mappings = data.authentik_property_mapping_provider_scope.scopes.ids

  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      redirect_uri_type = "authorization"
      url               = "https://argocd.sre.bakseter.net/api/dex/callback"
    }
  ]
}

resource "authentik_application" "argocd" {
  name              = "Argo CD"
  slug              = "argocd"
  protocol_provider = authentik_provider_oauth2.argocd.id

  meta_icon = "https://landscape.cncf.io/logos/ba71fd50cbc06c7bad3554de23cbca4298593141df3842003a94065c209610f4.svg"
}

resource "authentik_group" "argocd-admins" {
  name  = "argocd-admins"
  users = [data.authentik_user.a.id]
}

resource "authentik_policy_binding" "argocd-access" {
  for_each = toset([
    authentik_group.argocd-admins.id,
  ])

  target = authentik_application.argocd.uuid
  group  = each.key
  order  = 0
}


#### Grafana

resource "authentik_provider_oauth2" "grafana" {
  name      = "grafana"
  client_id = "grafana"

  authorization_flow = data.authentik_flow.default-provider-authorization-implicit-consent.id
  invalidation_flow  = data.authentik_flow.default-provider-invalidation-flow.id

  sub_mode = "user_username"

  signing_key       = data.authentik_certificate_key_pair.default.id
  property_mappings = data.authentik_property_mapping_provider_scope.scopes.ids

  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      url               = "https://grafana.sre.bakseter.net/login/generic_oauth"
      redirect_uri_type = "authorization"
    }
  ]

  logout_uri    = "https://grafana.sre.bakseter.net/logout"
  logout_method = "frontchannel"
}

resource "authentik_application" "grafana" {
  name              = "Grafana"
  slug              = "grafana"
  protocol_provider = authentik_provider_oauth2.grafana.id

  meta_icon = "https://upload.wikimedia.org/wikipedia/commons/a/a1/Grafana_logo.svg"
}

resource "authentik_group" "grafana-admins" {
  name  = "grafana-admins"
  users = [data.authentik_user.a.id]
}

resource "authentik_group" "grafana-viewers" {
  name  = "grafana-viewers"
  users = [data.authentik_user.e.id]
}

resource "authentik_policy_binding" "grafana-access" {
  for_each = toset([
    authentik_group.grafana-admins.id,
    authentik_group.grafana-viewers.id
  ])

  target = authentik_application.grafana.uuid
  group  = each.key
  order  = 0
}

resource "authentik_application_entitlement" "grafana-admins" {
  name        = "Grafana Admins"
  application = authentik_application.grafana.uuid
}

resource "authentik_application_entitlement" "grafana-viewers" {
  name        = "Grafana Viewers"
  application = authentik_application.grafana.uuid
}

resource "authentik_policy_binding" "grafana-admins-entitlement" {
  target = authentik_application_entitlement.grafana-admins.id
  group  = authentik_group.grafana-admins.id
  order  = 0
}

resource "authentik_policy_binding" "grafana-viewers-entitlement" {
  target = authentik_application_entitlement.grafana-viewers.id
  group  = authentik_group.grafana-viewers.id
  order  = 0
}


#### five31

resource "authentik_provider_oauth2" "five31" {
  name      = "five31"
  client_id = "five31"

  authorization_flow = data.authentik_flow.default-provider-authorization-implicit-consent.id
  invalidation_flow  = data.authentik_flow.default-provider-invalidation-flow.id

  sub_mode = "user_username"

  signing_key       = data.authentik_certificate_key_pair.default.id
  property_mappings = data.authentik_property_mapping_provider_scope.scopes.ids

  access_token_validity  = "hours=1"
  refresh_token_validity = "days=30"

  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      redirect_uri_type = "authorization"
      url               = "https://five31.bakseter.net/oauth2/callback"
    }
  ]
}

resource "authentik_application" "five31" {
  name              = "5/3/1 Program"
  slug              = "five31"
  protocol_provider = authentik_provider_oauth2.five31.id

  meta_launch_url = "https://five31.bakseter.net"
}

resource "authentik_group" "five31-users" {
  name = "five31-users"
  users = [
    data.authentik_user.a.id,
    data.authentik_user.n.id,
  ]
}

resource "authentik_policy_binding" "five31-access" {
  target = authentik_application.five31.uuid
  group  = authentik_group.five31-users.id
  order  = 0
}


#### mandagsmiddag

resource "authentik_provider_oauth2" "mandagsmiddag" {
  name      = "mandagsmiddag"
  client_id = "mandagsmiddag"

  authorization_flow = data.authentik_flow.default-provider-authorization-implicit-consent.id
  invalidation_flow  = data.authentik_flow.default-provider-invalidation-flow.id

  sub_mode = "user_username"

  signing_key       = data.authentik_certificate_key_pair.default.id
  property_mappings = data.authentik_property_mapping_provider_scope.scopes.ids

  access_token_validity  = "hours=1"
  refresh_token_validity = "days=30"

  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      redirect_uri_type = "authorization"
      url               = "https://mandagsmiddag.no/oauth2/callback"
    }
  ]
}

resource "authentik_application" "mandagsmiddag" {
  name              = "mandagsmiddag"
  slug              = "mandagsmiddag"
  protocol_provider = authentik_provider_oauth2.mandagsmiddag.id

  meta_launch_url = "https://mandagsmiddag.no"
  meta_icon       = "https://mandagsmiddag.no/icon.png"
}

/*
resource "authentik_group" "mandagsmiddag-users" {
  name = "mandagsmiddag-mandagsmiddag"
  users = []
}

resource "authentik_policy_binding" "mandagsmiddag-access" {
  target = authentik_application.five31.uuid
  group  = authentik_group.five31-users.id
  order  = 0
}
*/


#### RBAC

data "authentik_user" "a" {
  pk = "17"
}

data "authentik_user" "e" {
  pk = "19"
}

data "authentik_user" "n" {
  pk = "67"
}

resource "authentik_group" "mandagsmiddag-admins" {
  name = "mandagsmiddag-admins"
  users = [
    data.authentik_user.a.id,
    data.authentik_user.e.id,
  ]
}
