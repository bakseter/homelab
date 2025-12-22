locals {
  cluster_name  = "homelab"
  talos_version = "v1.12.0"

  config = yamldecode(
    templatefile(
      "${path.module}/manifests/config.yaml",
      {
        talos_version = local.talos_version,
        # TODO: Find way to not hardcode this value, cannot use output from resource because of for_each
        talos_schematic_id   = "077514df2c1b6436460bc60faabc976687b16193b8a1290fda4366c69024fec2"
        extension_image_refs = data.talos_image_factory_extensions_versions.talos.extensions_info.*.ref,
      }
    )
  )

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
}
