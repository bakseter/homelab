locals {
  config = yamldecode(file("${path.module}/config.yaml"))

  nodes = { for name, node in local.config.nodes : name => node }
  virtual_nodes = merge([
    for name, node in local.nodes : {
      for idx, v_node in node.virtualNodes :
      "${name}-${v_node.type}-${idx + 1}" => merge(v_node, { parent_node = name })
    }
  ]...)

  virtual_controlplane_nodes = { for name, node in local.virtual_nodes : name => node if node.type == "controlplane" }
  virtual_worker_nodes       = { for name, node in local.virtual_nodes : name => node if node.type == "worker" }

  main_virtual_controlplane_node = one(
    [for name, node in local.virtual_controlplane_nodes : node.ip if name == "m720q-controlplane-1"]
  )

  cluster_name  = "homelab"
  talos_version = "v1.12.0"
}
