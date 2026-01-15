locals {
  cluster_name            = "homelab"
  talos_version           = "v1.12.1"
  virtual_ip_controlplane = "192.168.1.190"

  config = yamldecode(
    templatefile(
      "${path.module}/manifests/config.yaml",
      {
        talos_version = local.talos_version,
        # TODO: Find way to not hardcode this value, cannot use output from resource because of for_each
        talos_schematic_id      = "88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b"
        extension_image_refs    = data.talos_image_factory_extensions_versions.talos.extensions_info.*.ref,
        virtual_ip_controlplane = local.virtual_ip_controlplane,
      }
    )
  )

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
