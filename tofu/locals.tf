locals {
  cluster_name            = "homelab"
  talos_version           = "v1.12.1"
  virtual_ip_controlplane = "192.168.1.190"

  config = yamldecode("${path.module}/manifests/config.yaml")

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
    [for name, node in local.virtual_controlplane_nodes : node.ip if name == "m720q-controlplane-1"]
  )
}
