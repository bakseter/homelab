locals {
  cluster_name          = "homelab"
  initial_talos_version = "v1.12.1"
  # Talos upgrades are managed via tuppr.
  # This sets the version for OpenTofu resources.
  # renovate: datasource=docker depName=ghcr.io/siderolabs/talos
  talos_version           = "v1.14.6"
  virtual_ip_controlplane = "192.168.30.190"

  config = yamldecode(file("${path.module}/manifests/config.yaml"))

  nodes = { for name, node in local.config.nodes : name => node }
  virtual_nodes = merge([
    for name, node in local.nodes : {
      for idx, v_node in node.virtualNodes :
      v_node.hostname => merge(v_node, { parent_node = name })
    }
  ]...)

  virtual_controlplane_nodes = { for name, node in local.virtual_nodes : name => node if node.type == "controlplane" }
  virtual_worker_nodes       = { for name, node in local.virtual_nodes : name => node if node.type == "worker" }

  main_virtual_controlplane_node = one(
    [for _, node in local.virtual_controlplane_nodes : node.ip if try(node.isMainControlplane, false)]
  )
}
